---
layout: post
title: "Least-privilege agents: runtime brokering and policy engines"
date: 2026-08-26T11:00:00+00:00
author: alxk
sitemap: false
keywords: "security ai agents kubernetes rbac opa vault"
description: "How to tightly scope an agent's privileges at runtime, using an SRE agent on Kubernetes as a worked example: credential brokering with Vault, policy engines with OPA, and enforcement points outside the agent container."
---

# Least-privilege agents: runtime brokering and policy engines

Identity and access management for agents is still evolving and the industry hasn't yet converged on standard practices.

In this post I work through one angle by demonstrating how to tightly scope an agent's privileges at runtime, using an "SRE agent" running on Kubernetes as an example. We'll discuss credential brokering, policy engines and enforcement points.

This simplified example is for educational purposes only. It's a demonstration of principles and what's possible; as always, security controls should be proportionate. For more production reading ideas and tools take a look at [Uber](https://www.uber.com/us/en/blog/solving-the-agent-identity-crisis/) and [agentgateway](https://github.com/agentgateway/agentgateway).

## Introduction

How do we apply the principle of least privilege to an agent?

For conventional services we know the drill: give them exactly the permissions they need to do their job, and nothing more. We can do this through some static analysis of the code or runtime analysis in a staging environment.

We typically don't know what agents will do until they're about to do it. The permissions ceiling for agents is deliberately large since we want them to respond to a broad range of scenarios that are not defined until runtime. But if we combine a surplus of permissions with untrusted input that can affect the control flow, we have a recipe for problems.

We can't stop an agent from being manipulated via attacker-controlled input (or from going haywire on its own), but we can shrink what its credentials permit when it does.

For the rest of this post I'm going to walk you through a simplified example of doing this with an "SRE agent" responding to incidents in Kubernetes.

## Where the surplus comes from

Let's assume a Kubernetes cluster with some services in the `prod` namespace monitored by Prometheus and Alertmanager in an `sre` namespace. We configured Alertmanager to trigger a webhook to spin up an SRE agent when there's an error rate spike in one of the `prod` services.

The SRE agent is expected to diagnose and fix any impacted `prod` service, so it is given a role with broad but sensible RBAC permissions on the `prod` namespace, allowing it to read logs and restart or scale services:

```
pods, pods/log, events → get, list, watch
apps/deployments, replicasets → get, list, watch
apps/deployments, deployments/scale → patch, update
```

In our example, let's just say that an incident is always isolated to a single service. In that case there's no need for these broad permissions over the entire namespace. But we don't know ahead of time which service will be impacted, and hardcoding a tailored SRE role for every service we run is not scalable, so we ended up with the permission set above.

Note also that an agent can get arbitrary code execution through the patch permission on a deployment (`command: ["sh","-c","..."]` in the pod spec). This could lead to lateral movement and privilege escalation. We'll discuss how we can tighten this.

## What can go wrong

This does however open the door to some attacks and alignment issues. For example, let's say some service logs reflect user input, allowing an attacker to plant a prompt injection. When the SRE agent investigates an outage it will end up loading poisoned logs into context.

With the permissions above, a successful prompt injection could lead to:

| A successful prompt injection could lead to | Why? |
|---|---|
| Scaling every service in the namespace to zero replicas | The role covers every deployment in the namespace, not just the impacted one |
| Scaling the impacted service to zero replicas | RBAC authorises the verb, not the value |
| Reading every service's logs, not just the impacted one | `get`/`list` on pods and logs is namespace-wide |
| Rewriting the pod spec to enable code execution | `patch` on a deployment rewrites the pod template |
| Inheriting a more privileged ServiceAccount in the namespace | The pod template includes `serviceAccountName`, so the agent can run the workload as any SA in the namespace |
| Reading the agent's credentials off the container filesystem | The token is mounted inside the agent's container |

The diagram below illustrates the setup and the attack flow:

![sre agent environment and prompt injection attack flow](https://alex.kaskaso.li/images/posts/least-privilege-agents/environment.png "sre agent environment and prompt injection attack flow")

## Scoping the credential at runtime

We can improve this by generating short-lived credentials at runtime. When we receive the Alertmanager webhook, we extract trusted fields *outside an attacker's control*, like the namespace and the impacted deployment (and we would not trust that information if it came from logs, for example).

We can then broker credentials for a role better scoped to our particular incident, and mint the token with Vault.

![brokering a short-lived scoped credential with vault](https://alex.kaskaso.li/images/posts/least-privilege-agents/vault.png "brokering a short-lived scoped credential with vault")

Our chosen example runs into some limitations of Kubernetes RBAC; we can't really restrict the scope of the read permissions since pod names of the impacted service may change during the incident, and the `list` verb can't be scoped with RBAC anyway. We can however restrict `patch` and `update` permissions to the impacted deployment, putting us in a better position.

At this point our SRE agent can no longer scale all production services to zero replicas and cause a general outage; it can only affect the impacted service.

| Attack | Closed by credential scoping |
|---|---|
| Scaling every service in the namespace to zero replicas | ✅ |
| Scaling the impacted service to zero replicas | ❌ |
| Reading every service's logs, not just the impacted one | ❌ |
| Rewriting the pod spec to enable code execution | ❌ |
| Inheriting a more privileged ServiceAccount in the namespace | ❌ |
| Reading the agent's credentials off the container filesystem | ⚠️ |

⚠️ The agent can still access the credentials but they are now short lived.

## Further scoping the request with a policy engine

In Kubernetes we can go beyond built-in RBAC. We can create request-content-aware policies with a policy engine like Open Policy Agent, and a policy enforcer like an Envoy sidecar proxy.

![opa and envoy sidecar enforcing request-content-aware policy](https://alex.kaskaso.li/images/posts/least-privilege-agents/opa.png "opa and envoy sidecar enforcing request-content-aware policy")

One limitation of our previous RBAC approach is that we can't restrict read permissions to impacted pods and their logs. With OPA we can deny requests that don't contain a label selector of `labelSelector=app=impacted-service` on list requests. Similarly we can enforce a prefix like `startswith(pod, "impacted-service-")` on pod logs requests. Our agent can now only investigate the impacted service.

We can also fix the arbitrary code execution via the `patch` verb by allowlisting what the agent may change. For example, by only allowing the rollout restart annotation.

We also noted that with the coarse RBAC approach, our agent could scale the impacted service to zero replicas. We can now use our policy engine to enforce any replica scaling to be `>= 1`.

Note that policy enforcement here happens _outside_ the agent container. As a bonus, our access token can be injected into the request by the proxy, meaning a compromised agent with access to its own container's filesystem can no longer read the credential.

At this point we've made substantial progress in locking down our agent:

| Attack | Credential scoping | Policy engine |
|---|---|---|
| Scaling every service in the namespace to zero replicas | ✅ | ✅ |
| Scaling the impacted service to zero replicas | ❌ | ✅ |
| Reading every service's logs, not just the impacted one | ❌ | ✅ |
| Rewriting the pod spec to enable code execution | ❌ | ✅ |
| Inheriting a more privileged ServiceAccount in the namespace | ❌ | ✅ |
| Reading the agent's credentials off the container filesystem | ⚠️ | ✅ |

## How production differs

We'd do things differently in a real environment. First we'd centralise the logs on another platform like Loki or Datadog and give the agent read permissions there. Cluster and deployment status may also be viewed through an observability platform.

As of August 2026, I would recommend focusing agents on root cause analysis and suggesting remedial actions, leaving the prod fixes to human SREs. This advice may change though.

## Conclusion

We saw that we can deploy an agent in Kubernetes with runtime scoped permissions that reduce the blast radius if things go wrong.

In our worked example, we can think of RBAC as a coarse permissions ceiling, with the policy engine narrowing the privileges on a per-request basis.

The principles we discussed here apply more broadly to agents outside Kubernetes. The catch is that your policy has to stay in step with what the agent is allowed to do.
