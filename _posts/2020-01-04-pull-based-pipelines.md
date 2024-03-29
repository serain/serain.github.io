---
layout: post
title: "Security advantages of pull-based CD pipelines"
date: 2020-01-04T23:00:55+00:00
author: alxk
sitemap: false
keywords: "security kubernetes docker ci cd"
description: "Securing CI/CD pipelines with a pull-based approach"
---

# Pull-based CD pipelines

We recently adopted [GitOps](https://www.weave.works/technologies/gitops/) for Kubernetes deployments, using Weaveworks' _[flux](https://www.weave.works/oss/flux/)_ daemon. This is a "pull-based" approach to continuous deployment for k8s, very much pioneered by Weaveworks' themselves.

There's several advantages to this but what I'm going to focus on here are the security benefits. I'm then going to advocate for the adoption of the pull-based CD approach beyond k8s manifests, particularly around building and pushing container images.

Ultimately, I'm arguing that "CI/CD" tools like CircleCI and Jenkins are a security hazard and should only be used for "CI" (running tests).

![devops unicorn](https://alex.kaskaso.li/images/posts/devops-security-unicorn.png "devops unicorn"){: .center-image }

## Note

I originally published this on [Medium](https://medium.com/@alexkaskasoli/pull-based-cd-pipelines-for-security-4e044b403f56). It is reproduced here as a mirror.

This post got picked up by [Google's Kubernetes podcast](https://kubernetespodcast.com/episode/086-invention-ibm-istio/) and [CloudSecList](https://cloudseclist.com/issues/issue-19/).

## Hazards of push-based CI/CD tooling

Let's define "push-based" in this context. If you're using something like CircleCI or Jenkins to deploy, those tools are _pushing_ your services:

- they're building and _pushing_ your image to a container registry
- they're _pushing_ your updated manifests to production

So the engineers have access to the CI/CD tooling, and the CI/CD tooling has access to production. It looks like this (note the direction of the arrows):

![traditional pipeline](https://alex.kaskaso.li/images/posts/traditional_pipeline.png "traditional pipeline"){: .center-image }

We'll see how this contrasts with a pull-based approach later.

First, what's the issue with tools like Jenkins or CircleCI for deployment? My main security arguments against traditional CI/CD tools are:

- the network attack surface
- disappointing access controls over secrets (looking at you CircleCI)
- yet another third-party with your deployment secrets (for SaaS)

### Network attack surface

Minimizing your attack surface is a basic security principle.

Let's say you have something like Jenkins running on your network. There's [150 CVEs for Jenkins core](https://www.cvedetails.com/vulnerability-list.php?vendor_id=15865&product_id=34004&version_id=&page=1&hasexp=0&opdos=0&opec=0&opov=0&opcsrf=0&opgpriv=0&opsqli=0&opxss=0&opdirt=0&opmemc=0&ophttprs=0&opbyp=0&opfileinc=0&opginf=0&cvssscoremin=0&cvssscoremax=0&year=0&month=0&cweid=0&order=1&trc=150&sha=42dfa4c7d4f30241bc7fa7cb4e94138bcf01a35e), with 15 of those just from 2019. This figure excludes plugin vulnerabilities - [of which there are many more](https://jenkins.io/security/advisories/) (not to mention the risk of supply-chain attacks with those).

To add to the fun, [_reflected_ Cross-Site Scripting in Jenkins](https://www.google.com/search?client=firefox-b-d&q=jenkins+reflected+xss) can lead to remote code execution on the Jenkins host, meaning attackers can probably gain an initial foothold into [quite a few companies](https://crt.sh/?q=jenkins.%25) with some innocuous phishing or watering hole attacks (you did click on a random link to view this blog post, didn't you? 🙃).

RCE on your Jenkins host is bad enough, but if you have production deployment secrets on there it's game over.

### Free-for-all secrets

![oprah secrets](https://alex.kaskaso.li/images/posts/oprah_secrets.jpg "oprah secrets"){: .center-image }

I'll talk about CircleCI here but this applies to other CI/CD tools.

Everything is Agile and DevOps, so you want to allow your engineers to deploy multiple times a day, with minimal friction.

You have branch protections on your `master` branch and require one or more peer review of changes before a branch can be merged into `master`. So the CI/CD flow you'd expect is maybe something like:

- Alice pushes a new branch with some changes
- CircleCI runs some tests in the branch
- Bob reviews Alice's branch and approves the changes
- Alice merges branch into `master`
- CircleCI, from `master`:
  - runs tests again
  - builds image
  - pushes image to the container registry
  - deploys

It may be tempting to think that only CircleCI has access to deployment secrets in the scenario above, or that only a peer-reviewed `master` branch can be pushed to your container registry and deployed to production.

In fact Alice, Bob and everyone else on that team can trivially pull the deploy secrets out, and CircleCI's [contexts](https://circleci.com/docs/2.0/contexts/) offer little solace here as long as you want to empower the team to deploy on their own. To pull the secrets out you just need to push a branch and print out the environment variables during a job run, or POST them to an endpoint - after all, CI/CD tooling is literally Code-Execution-as-a-Service.

In the above scenario, compromising a single engineer is enough to gain access to production through CircleCI (at least to the extent their context allows).

It should be noted that Travis and other solutions offer better controls, allowing you to restrict secrets on a per-branch basis. You would therefor only expose deployment secrets to `master` code that's been peer-reviewed (and therefor assumed safe). Still, that's production deployment secrets outside of the trust boundary of your production environment. As we'll see later, this is not necessary.

### Sharing is not caring

It seems to be fashion these days to share your deepest secrets with everyone.

There's companies like [Platform9](https://platform9.com/) or [Spotinst](https://spotinst.com/) who want admin access to your cloud environment or production cluster to help you manage things. Of course, you're also expected to give this access to your CI/CD SaaS of choice, if you're going for the Cloud version.

This is all the more worrying given that [some threat actors are known to have shifted their focus to targeting managed service providers](https://www.ncsc.gov.uk/information/global-targeting-enterprises-managed-service-providers); why put the effort into compromising a thousand companies when they can target a single service provider and gain access to all their customers?

To a certain extent, you have to trust third-parties these days. However, I'm more comfortable with AWS lording over my services than a startup or small company who may be cutting corners around security while they focus on market acrobatics.

At the end of the day, you just want to limit the number of third-parties with access to your stuff.

## "pull-based" deployments with flux

How does adopting the pull-based approach offered by _flux_ improve the security posture here?

For those not in the loop, the _flux_ daemon sits _inside your k8s cluster_ and does two things:

- it _pulls_ k8s manifests from a git repo, and applies them to the cluster
- it monitors your container registry for newer images, and updates your k8s resources accordingly

I'll just focus on the first point here for brevity ([the docs](https://docs.fluxcd.io/en/1.17.0/introduction.html#introducing-flux) give a good intro to the rest).

_flux_ regularly polls the `master` branch of the repo that contains your k8s YAML manifests and makes sure that what's in your cluster matches what's defined in the "GitOps" repo. In the simplest terms, this is what it does:

```bash
while true
do
git clone git@github.com:foo/gitops-repo.git
kubectl apply -f gitops-repo/
sleep 300
done
```

And just like that, the state of your cluster is version controlled, auditable and protected from drift. You can go ahead and revoke everyone's access to the cluster; they don't need `kubectl` anymore.

More importantly though, you can go ahead and remove cluster access from your CI/CD tool. Your CD pipeline now looks like this (notice the direction of the arrows):

![gitops pipeline](https://alex.kaskaso.li/images/posts/gitops_pipeline.png "gitops pipeline"){: .center-image }

Because your CD tool now sits in your k8s cluster and uses a _pull-based_ approach, an attacker would already need privileged access to your cluster to abuse it (read: there's no point attacking the CD tool now).

_flux_ has no network attack surface and doesn't leak secrets.

Your deployment access controls are now in your GitOps git repo and you probably want:

- branch protections on `master`
- a number of peer-reviews
- require reviews from team members using CODEOWNERS

With these measures, multiple engineers from the same team need to be compromised for an attacker to make his way to production through the CD pipeline.

## What about the images?

In the previous section I said "your CD tool now sits in your k8s cluster" but that's only partially true. If you only adopt Weaveworks' _flux_ and call it a day, you're still _pushing_ your Docker images to a container registry, probably using a CI/CD tool like Jenkins or CircleCI.

In fact, that's what Weaveworks explicity say in their own [blog posts](https://www.weave.works/blog/continuous-delivery-weave-flux/) which is a bit surprising; they're lauding the security benefits of their _pull-based_ k8s deployment approach while recommending their users _push_ images to a container registry, and from CircleCI nonetheless (image from Weaveworks):

![weaveworks pipeline](https://alex.kaskaso.li/images/posts/weaveworks_pipeline.png "weaveworks pipeline"){: .center-image }

So we've not really solved the problem at this point. If the CI/CD tool is compromised according to one of the scenarios we described above, attackers can push arbitrary images to the container registry. Given that _flux_ also [automates the deployment of new images by monitoring the container registry](https://docs.fluxcd.io/en/1.17.0/introduction.html#automated-deployment-of-new-container-images), that's still a CI/CD path to production to be abused by attackers.

## Pull-based image builds

The solution seems straightforward at this point: building and adding new images to the container registry should also be done with a pull-based approach. We need a daemon that polls application repositories for peer-reviewed (trusted) changes to `master`. Upon a change, it builds the application's Dockerfile and safely puts the image in the container registry.

What we're looking for is something like this (again, arrows):

![pull pipeline](https://alex.kaskaso.li/images/posts/pull_pipeline.png "pull pipeline"){: .center-image }

Such a service would have no network attack surface and wouldn't risk leaking any image deployment secrets.

I've been playing around with a proof-of-concept that polls repos and uses Google's [_kaniko_](https://github.com/GoogleContainerTools/kaniko) to build images in a safe location.

## TL;DR

We need to turn our pipelines around and start pulling.

Traditional push-based CI/CD tools are a security hazard. It’s true that some offer better security controls than others, but either way, there are tangible security benefits with pull-based pipelines.

Continuous deployment can and should only be done within the trust boundary of your production environment.

We now need a solid pull-based tool for building images to complement _flux_.
