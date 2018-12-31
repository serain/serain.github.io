---
layout: post
title: "Effective Security Pipeline"
date: 2018-12-30T23:03:25+00:00
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

Rather than dive into configuration details, this post will provide an overview of the steps you may wish to integrate into a DevSecOps pipeline, regardless of the CI stack you are using. We assume we are dealing with a pretty standard dockerized web application, although the principles apply more broadly.

## Continuous Integration Pipeline

The image below illustrates a standard CI pipeline that you may already be using:

![ci pipeline](https://alex.kaskaso.li/images/posts/ci-pipeline.png "ci pipeline"){: .center-image }

We'll extend this pipeline to include the security checks that we'll discuss in the following sections:

![devsecops ci pipeline](https://alex.kaskaso.li/images/posts/devsecops-pipeline.png "devsecops ci pipeline"){: .center-image }

## Recurring Builds for Continuous Security

Pipelines are typically run in response to a developer-triggered event, such as pushing code.

But let's assume that an application has reached a stable production state and is no longer under active development; when the developers pushed the last code changes, the pipeline succeeded without any errors and all dependencies were up to date and secure.

Let's imagine that a month after this last build a critical issue was released for one of the dependencies. This issue may go undiscovered until a developer pushes another change or a pentester comes along and looks at the application.

To provide coverage in these cases, "cron jobs" should be configured to ensure the pipelines run on a daily basis. With this setup, the development team will be alerted to new vulnerabilities in third-party dependencies as they arise.

## Dockerfile Linting

Dockerfiles essentially define the environment a dockerized application will be running in. A combination of `Dockerfile` linting tools (such as [`hadolint`](https://github.com/hadolint/hadolint)) and custom scripts can be used to ensure the Dockerfile passes a series of security checks:

* Don't use `:latest`

The `:latest` tag tells Docker to use the latest version of a base image to build an application image. While this may sound like good practice, it runs the risk of including any recent developments in the base image (new dependencies or binaries) that could present a risk to our application. It is safer to ensure developers pin against a specific version that has been reviewed and considered secure.

* Don't run as `root`

The principle of least privileges: we'll assume that the application will get breached, and when it does we want to ensure attackers are left with the low privileges inside the container. We therefor want to ensure developers are dropping privileges by the end of Dockerfile.

* Enforce select base images

Minimalist and security-conscious base images, such as Amazon Linux or Alpine Linux, should be favored. Larger distributions like Ubuntu are not necessarily insecure, but provide an unnecessarily large attack surface and are not generally thought of as security-focussed distributions.

* Remove unnecessary or `setuid` binaries

If your image ships with `curl` or `nc`, chances are your application doesn't need them, but an attacker would find them handy. Similarly, unnecessary `setuid` binaries could offer paths to privilege escalation. As much as possible, ensure developers are removing unnecessary binaries by the end of the Dockerfile.

* Enforce hash checks on `curl` and `wget`

Developers will occasionally directly download external dependencies in the Dockerfile. If doing so you want to ensure that the checksums are validated to prevent supply-chain or man-in-the-middle attacks on your dependencies.

## Dependency Checks

Modern package managers, such as [`Pipenv`](https://pipenv.readthedocs.io/en/latest/) for Python or `npm` for Node.js, maintain up-to-date lists of vulnerabilities in their packages and provide command-line utilities to quickly check for these.

A simple `pipenv check` or `npm audit` in the pipeline will fail if any known vulnerabilities are present in the packages used by the application.

It is important to note that it may not be practical to enforce a zero tolerance policy on all potential security issues. Naturally any issue that presents a risk should be removed; however developers may be left with issues that present minimal or unproven risks, or an issue that can only be exploited in peculiar scenarios unlikely to be present in the application. Such issues may be explicitely ignored through command-line arguments, provided they have been reviewed and understood.

## Static Analysis

## Secure Builds with Docker

## Image Scanning

## Dynamic Analysis

## Auto-Update Dependencies

## Conclusion
