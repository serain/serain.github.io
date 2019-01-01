---
layout: post
title: "Revisiting Email Spoofing"
date: 2018-12-31T18:58:35+00:00
author: alxk
sitemap: false
keywords: "redteam email spf dkim dmarc pentest"
description: ""
---

# Revisiting Email Spoofing

Email spoofing is still a thing, and some organisations are likely at risk of receiving legitimate-looking phishing emails from spoofed domains.

This post will give a cursory overview of the methods used to prevent email spoofing and introduce a tool to remotely identify domains with misconfigured anti-spoofing measures.

I will also outline an interesting way I was able to bypass an organisation's "EXTERNAL" email filter to phish employees with trusted internal emails.

## SPF, DKIM and DMARC

Email dates from the days the Internet was a trusted network and people were expected to behave. As such, the original protocols simply trust senders to be who they say they are. You can send an email claiming to be Google, the President or anyone else from any box on the internet using a tool like `sendmail`.

The onus is on recipients to verify the identity of email senders. To this end, three protocols were introduced. These are explained in a cursory and rather simplified manner in this post; readers interested in a more detailed introduction are encouraged to start by the respective Wikipedia pages.

### Sender Policy Framework (SPF)

SPF lets recipients know which IP addresses a domain owner expects his emails to originate from. To enable SPF, the domain owner must configure a special DNS TXT record. An SPF record for the fictional Contoso organisation is shown below:

```
$ dig +short txt contoso.com
"v=spf1 ip4:147.243.128.24 ip4:147.243.128.25 -all"
```

This record indicates that the owners of `contoso.com` expect emails from `@contoso.com` to originate from either `147.243.128.24` or `147.243.128.25` on the Internet. If the recipient is getting this email via a TCP connection from another source IP, the email should fail SPF validation.

The qualifier of the last argument `all` is important:

* `-all` is a _hard fail_: if the email fails SPF validation, the `contoso.com` owners want the email to be discarded
* `~all` would be a _soft fail_; if the email fails SPF validation, the `contoso.com` owners wish the email to be allowed through, but treated as slightly suspcious (by, for example, raising a spam score).

### DomainKeys Identified Mail (DKIM)

DKIM allows senders to sign emails by adding an email header containing a signature and the information necessary to fetch the public key needed to validate the signature.

An example DKIM signature header is shown here:

```
DKIM-Signature: v=1; a=rsa-sha256; d=example.com; s=news;
c=relaxed/relaxed; q=dns/txt; t=1126524832; x=1149015927;
h=from:to:subject:date:keywords:keywords;
bh=MHIzKDU2Nzf3MDEyNzR1Njc5OTAyMjM0MUY3ODlqBLP=;
b=hyjCnOfAKDdLZdKIc9G1q7LoDWlEniSbzc+yuU2zGrtruF00ldcF
VoG4WTHNiYwG
```

In the example above, the `bh` value is a hash of the email body while the `b` value contains the signature. Recipients can use the `s` selector value to fetch the public key via DNS:

```
$ dig +short txt news._domainkey.example.com
"k=rsa; t=s; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQChK0RIGEj4ahkPXIhENbmXC6Cu2Q1eVNDM6nZdrJGR2p4jWYNVGQ/EYQRC35Qu+rBcvNvayv8igvCou1A9Y6xso1ls6MCMpT3LjatFo+U+qfMI9Uh6P0sQ+NNS7NAGc0GGl8bAxi+mbG0AHgbgrB6DTJwAz7uGd0IzjPtPdn5EuQIDAQAB"
```

### Domain Message Authentication Reporting & Conformance

DMARC is simply a way to tell recipients how to treat emails that fail SPF and DKIM validation, and where to send reports to help domain owners identifiy dubious activity and debug issues. DMARC is also configured via a DNS TXT record:

```
$ dig +short txt _dmarc.contoso.com
"v=DMARC1; p=reject; rua=mailto:report@contoso.com; ruf=mailto:d@contoso.com;"
```

The policy value `p` tells recipients how to treat emails that fail SPF and DKIM validation. A policy of `reject`, as you guessed it, instructs recipients to discard such emails. The `rua` and `ruf` values specify emails to send two different typos of diagnostic reports to.

## The Bad

Why people use soft fails, why many organisations have poor SPF and DMARC (marketing).

## The Ugly

A lot of people have SPF, DKIM and DMARC validation turned off. I can't give precise numbers because I've not reviewed a large sample of systems, but I've seen these explicitely disabled often enough to know that it is a possibility and something red teams and attackers can abuse to spoof emails from trusted domains on the internet.

## Bypassing "EXTERNAL" Filters

Map an organisation's parent and subsidiary companies. Some of these may have poor SPF, DMARC. Some of these may be whitelisted so that emails from them are treated as internal.

I was able to use this to send emails to an organisation by impersonating any source. For example "sysadmin@parent_company.com".

## `mailspoof`

Tool.

## Recommendations

If you're an organisation:

* Review your email filter: ensure SPF, DKIM and DMARC validation are enabled. Emails that fail validation should be quarantined.

* If you need to whitelist external domains, or treat them as internal domains, check that their SPF and DMARC records are well configured.

* Review your own SPF and DMARC records. You want SPF to _hard_ fail and DMARC to have a `reject` policy.

* Monitor your DMARC reports to gain insights into attempts to misuse your domain.
