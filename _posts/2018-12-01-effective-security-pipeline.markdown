---
crosspost_to_medium: true
layout: post
title: "Effective Security Pipeline"
date: 2018-12-01T23:03:25+00:00
author: alxk
sitemap: false
keywords: "devsecops pipeline docker security"
description: "Building an effective DevSecOps pipeline to catch security issues both during development and continuously in production."
---

# Effective Security Pipeline

In this post we'll walk through the main components of a DevSecOps Continuous Integration pipeline. This will allow us to catch security issues both during development and on a continuous basis in production.

## Introduction

Pentests against specific applications can't yet be fully automated. Logic flaws and complex security issues require hands-on knowledge from specialized consultants. However, several categories of issues can be reliably detected with automated scans, including:

* Outdated and vulnerable dependencies and software
* Misconfigured cookies and HTTP headers
* Default index pages
* Verbose stack traces
* Default credentials
* Textbook versions of OWASP Top 10

Readers will recognize that some of these issues were the source of several recent high profile breaches. These issues also typically account for up to half of the findings on an average pentest report.

By extending a traditional Continuous Integration (CI) pipeline, we can catch these issues as they arise in an application and provide a form of continuous assurance against new vulnerabilities, even when the application is not under active development. Combined with developer education, these measures can limit the reliance on regular pentests to keep an application secure, offering more cost-effective security.

The post will also cover services that can automatically manage security updates in your third-party dependencies.

Rather than dive into configuration details, this post will provide an overview of the steps you may wish to integrate into a DevSecOps pipeline, regardless of the CI stack you are using. We assume we are dealing with a pretty standard dockerized web application, although the principles apply more broadly.

## Continuous Integration Pipeline

The image below illustrates a standard CI pipeline that you may already be using:

![ci pipeline](https://alex.kaskaso.li/images/posts/ci-pipeline.png "ci pipeline"){: .center-image }

We'll extend this pipeline to include the security checks that we'll discuss in the following sections:

![devsecops ci pipeline](https://alex.kaskaso.li/images/posts/devsecops-pipeline.png "devsecops ci pipeline"){: .center-image }

## Recurring Builds for Continuous Security

Before diving into the meat of the subject, a quick note on why pipelines should run regularly.

CI pipelines are typically run in response to a developer-triggered event, such as pushing code or opening a merge request.

But let's assume that an application has reached a stable production state and is no longer under active development; when the developers pushed the last code changes, the pipeline succeeded without any errors and all dependencies were up to date and secure.

Let's imagine that a month after this last build a critical issue was released for one of the dependencies. This issue may go undiscovered until a developer pushes another change or a pentester comes along and looks at the application.

To provide coverage in these cases, "cron jobs" should be configured to ensure the pipelines run on at least on a daily basis. With this setup, the development team will be alerted to new vulnerabilities in third-party dependencies as they arise.

## Dockerfile Linting

Dockerfiles essentially define the environment a dockerized application will be running in. A combination of `Dockerfile` linting tools (such as [`hadolint`](https://github.com/hadolint/hadolint)) and custom scripts can be used to ensure the Dockerfile passes a series of security checks:

* **Don't use `:latest`**

The `:latest` tag tells Docker to use the latest version of a base image to build an application image. While this may sound like good practice, it runs the risk of including any recent developments in the base image (new dependencies or binaries) that could present a risk to our application. It is safer to ensure developers pin against a specific version that has been reviewed and considered secure.

* **Don't run as `root`**

The principle of least privileges: we'll assume that the application will be compromised, and when it does we want to ensure attackers are left with low privileges inside the container. We therefor want to ensure developers are dropping privileges by the end of Dockerfile.

* **Enforce select base images**

Minimalist and security-conscious base images, such as Amazon Linux or Alpine Linux, should be favored. Larger distributions like Ubuntu are not necessarily insecure, but provide an unnecessarily large attack surface and are not generally thought of as security-focused distributions.

* **Remove unnecessary or `setuid` binaries**

If your image ships with `curl` or `nc`, chances are your application doesn't need them, but an attacker would find them handy. Similarly, unnecessary `setuid` binaries could offer paths to privilege escalation. As much as possible, ensure developers are removing unnecessary binaries by the end of the Dockerfile.

* **Enforce hash checks on `curl` and `wget`**

Developers will occasionally directly download external dependencies in the Dockerfile. If doing so you want to ensure that the checksums are validated to prevent supply-chain or man-in-the-middle attacks on your dependencies.

## Dependency Checks

Modern package managers, such as [`Pipenv`](https://pipenv.readthedocs.io/en/latest/) for Python or `npm` for Node.js, maintain up-to-date lists of vulnerabilities in their packages and provide command-line utilities to quickly check for these.

A simple `pipenv check` or `npm audit` in the pipeline will fail if any known vulnerabilities are present in the packages used by the application.

It is important to note that it may not be practical to enforce a zero tolerance policy on all potential security issues. Naturally any issue that presents a risk should be removed; however developers may be left with issues that present minimal or unproven risks, or an issue that can only be exploited in peculiar scenarios unlikely to be present in the application. Such issues may be explicitly ignored through command-line arguments, provided they have been reviewed and understood.

## Static Analysis

FOSS static analysis tools are a mixed bag. In general they won't be useful, but if they ever are, we'll be really grateful. These tools parse application code looking for textbook cases of bad coding practices, such as passing user input directly to a shell or using a common library with a blatantly bad configuration.

As the cost of integrating one of these tools into the pipeline is fairly low, it is a worthwhile time investment.

You are likely to come across a number of false positives when using these tools; any noise causing the build process to fail may be whitelisted.

The [Awesome Static Analysis](https://github.com/mre/awesome-static-analysis) repository has a curated list of static analysis tools for most languages.

## Secure Builds with Docker

There are additional security checks that can be integrated into the pipeline, but these will have to be run using a built image. Before that, there is a Docker flag we can use during the build process to ensure the build is done in the safest way possible.

* **Use Docker Content Trust**

Docker Content Trust (DCT) allows Docker clients to verify the integrity and the publisher of image tags. This essentially guarantees that the base images have been pushed by trusted publishers and mitigates supply-chain or man-in-the-middle type attacks during the build process. DCT can be enabled by setting the `DOCKER_CONTENT_TRUST` environment variable with:

```
$ export DOCKER_CONTENT_TRUST=1
```

## Image Scanning

There are several solutions that will scan an image for security issues, such as vulnerable binaries and libraries. Among the free and open source ones, [Clair](https://github.com/coreos/clair) is currently the front-runner, although integration into a CI pipeline requires a certain amount of effort.

Clair feeds on various sources, such as NIST and various Linux distribution bug trackers, to maintain an up to date list of vulnerabilities. When new issues are added to the database it can send out alerts if any images previously scanned will be affected.

## Dynamic Analysis

As a last security check in our pipeline, we want to consider running an automated web application scan. A popular option to cover a lot of basic web vulnerability checks is [Zed Attack Proxy](https://www.owasp.org/index.php/OWASP_Zed_Attack_Proxy_Project) from OWASP, which can easily be integrated into most pipelines. There is even an [offical Jenkins plugin](https://wiki.jenkins.io/display/JENKINS/zap+plugin#zapplugin-ZAPasapartofaCIEnvironment).

It is important to understand what we can hope to achieve by including an automated web application scan. We are not looking for logic issues or any convoluted chain of attack; for those we are better off relying on qualified security consultants. Rather, we want to catch trivial but recurrent issues such as:

* Default passwords
* Missing CSRF tokens
* Misconfigured cookies
* Missing or misconfigured headers
* Debug messages

Mozilla published a [blog post](https://blog.mozilla.org/security/2017/01/25/setting-a-baseline-for-web-security-controls/) on how it uses ZAP with its CI environment.

## Auto-Update Dependencies

There are services that can monitor your codebase and automatically update your third-party dependencies as security issues are released. [Greenkeeper](https://greenkeeper.io/) provides this service for Node.js repositories.

These services work by parsing your codebase for third-party dependencies. When a security update is available, they create a new branch in your repository, update the dependencies to the latest stable and secure version, and open a merge request. Assuming that your test pipeline succeeds, hopefully indicating that the update does not break your application, a developer can simply approve the merge request.

## Conclusion

By integrating simple security checks into the CI pipeline we can eliminate several categories of issues, taking the brunt work away from pentesters and providing more cost-effective security.

This not only prevents some security hiccups during development, it also allows developers to effortlessly keep dependencies up to date across a large estate of applications.
