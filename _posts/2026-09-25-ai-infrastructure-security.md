---
layout: post
title: "AI cybersecurity evaluations: infrastructure security"
date: 2026-09-25T09:00:00+00:00
author: alxk
sitemap: false
keywords: ""
description: "How to contain actively hostile AI agents in cyber evaluations on public cloud: account-level isolation, sandboxed runtimes, egress control and detection."
---

# AI cybersecurity evaluations: infrastructure security

_This post is a draft, WIP_

When I founded the AI cybersecurity safety evaluations at Google DeepMind, we had to ask ourselves how to secure a workload that is actively hostile and, even in 2023, looked set to exceed human expert capabilities. The framework we built for cyber eventually grew to run most of our frontier safety evaluations.

What I describe here is not what we built on Google's internal infra, but rather a reflection of the principles applied to public cloud infra.

Not much has changed in the recommendations I would give to anyone else trying to contain these workloads in 2026 despite the huge jump in AI capabilities and the widely publicised "rogue AI" breaches of this year. I still believe basic defense-in-depth and least-privilege principles _applied systematically_ can greatly restrict the range of actions of AI agents.

To escape their sandboxes, we can force AI agents to find and exploit 0-days in much more contrived scenarios than what we've seen so far in the public breaches, and with some basic detection and response, we can likely catch them before they succeed.

Note that I focus only on the infrastructure security aspects here; I won't cover researcher UX and workload orchestration.

<figure>
  <a href="{{ site.url }}/images/posts/ai-infrastructure-security/agent.svg"><img src="{{ site.url }}/images/posts/ai-infrastructure-security/agent.svg" alt="Architecture: a trusted account and a hostile account joined by a one-way private link, both shipping logs to a dedicated logging account"></a></figure>

## Trusted and Hostile: account level segmentation

We distinguish between workloads that are trusted and those that should be considered actively hostile.

An agent harness loop _is trusted_; it runs inference against an LLM server, does some deterministic manipulation based on the output and extracts an untrusted command to run.

The execution environment and the target hacking challenge, where untrusted commands are run, are considered _actively hostile_. For the latter, the assumption is that you have some of the best hackers in the world sitting there, actively ignoring the scope of their exercise and trying to take over the whole environment instead.

In this example we run a Kubernetes cluster in each account. Importantly, the clusters are not federated. The only link between the two clusters is a unidirectional L4 network link from trusted to hostile, with an L7 relay/router using it.

Note that there is an attack path on that L4 network link; hostile agents can manipulate the responses from the execution environment to try to exploit parser vulnerabilities or other vulns in any system interacting with environment outputs. That's a trust boundary; treat env output as you would any untrusted input and use battle-tested parsers.

## Sandboxed container runtimes

Use gVisor on your trusted cluster where it will work, and on your restricted workloads in the hostile cluster.

For cybersecurity execution environments, you will likely want the agent to interact with a realistic kernel and gVisor's syscall stubbing/missing syscalls won't cut it. Go for Kata containers or an equivalent solution: Kata containers are micro VMs and give you a "natural" execution environment, and the hypervisor adds a layer of security forcing your agent to chain at least one additional hypervisor vulnerability to escape.

## L4 and L7 network policies

Inside the cluster, use L7 network policies where you can. In the hostile cluster in particular, if you're going to run something like Artifactory, allow-list the minimum required for your execution environments to pull packages. This is likely a GET request to a single HTTP path. Use an L4 default deny-all and allow-list the necessary.

Note that we have two different node pools for the hostile cluster. The execution environment and target challenges have VPC level firewall rules denying egress except to the "restricted" node pool running Artifactory. The "restricted" node pool has restricted internet egress to strictly required FQDNs. Even better, you can use something like Secure Web Proxy in GCP to enforce L7 policies at that level, restricting outbound HTTP paths there.

## No package registry

Consider skipping the registry and restricted internet egress entirely; bake packages directly into containers. This removes the need for any internet egress from your hostile cluster.

## IAM least privilege

Principle of least privilege everywhere. Audit both accounts to ensure there are no privilege escalation paths, especially from anywhere in the hostile cluster.

## Detection and response

Canary tokens and canary cloud resources; agents can't help themselves but try every token they find. Pepper them around the hostile account.

Move Cloud audit logs, DNS logs, k8s audit logs and k8s runtime security logs to a dedicated logging account.

You expect a bunch of suspicious behaviour on the untrusted nodes in the hostile cluster, but you do _not_ expect suspicious behaviour on the restricted nodes hosting your package registry or other support tooling! Set up your detection rules accordingly.

## CI/CD & admission control

_TODO_

## Test it

When you onboard a new frontier model, its first eval should be to break out of your infrastructure in a tightly audited evaluation. Spin that up in a separate project, instruct the models to promptly report back any findings, and adjust detection and response accordingly. Set up a dashboard and monitor the experiment (with humans).
