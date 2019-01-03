---
crosspost_to_medium: true
layout: post
title: "Revisiting Email Spoofing"
date: 2018-12-31T18:58:35+00:00
author: alxk
sitemap: false
keywords: "redteam email spf dkim dmarc pentest"
description: "Quick overview of SPF, DKIM and DMARC for red teamers, along with common misconfigurations and a potential external email filter bypass"
---

# Revisiting Email Spoofing

Email spoofing is still a thing and some organizations are at risk of receiving legitimate-looking phishing emails from spoofed domains.

This post will give a cursory overview of the methods used to prevent email spoofing and introduce a tool to remotely identify domains with misconfigured anti-spoofing measures.

I will also outline an interesting way I was able to bypass an organization's external email filter to phish employees with internal emails.

## SPF, DKIM and DMARC

Email dates from the days the Internet was a trusted network and people were expected to behave. As such, the original protocols simply trust senders to be who they say they are. You can send an email claiming to be Google, the President or anyone else from any box on the Internet using a tool like `sendmail`.

The onus is on recipients to verify the identity of email senders. To this end, three methods were introduced. These are explained in a cursory and rather simplified manner in this post; readers interested in a more detailed introduction are encouraged to start by the respective Wikipedia pages.

### Sender Policy Framework (SPF)

SPF lets recipients know which IP addresses a domain owner expects his emails to originate from. To enable SPF, the domain owner must configure a special DNS TXT record. An SPF record for the fictional Contoso organization is shown below:

```
$ dig +short txt contoso.com
"v=spf1 ip4:147.243.128.24 ip4:147.243.128.25 -all"
```

This record indicates that the owners of `contoso.com` expect emails from `@contoso.com` to originate from either `147.243.128.24` or `147.243.128.25` on the Internet. If the recipient is getting this email via a TCP connection from another source IP, the email should fail SPF validation.

The qualifier of the last argument `all` is important:

* `-all` is a _hard fail_: if the email fails SPF validation, the `contoso.com` owners want the email to be discarded.
* `~all` would be a _soft fail_; if the email fails SPF validation, the `contoso.com` owners wish the email to be allowed through, but perhaps be treated as slightly suspicious (by, for example, raising a spam score).
* `+all` would result in a pass regardless of the sources in the preceding arguments.

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

### Domain Message Authentication Reporting & Conformance (DMARC)

DMARC is simply a way to tell recipients how to treat emails that fail SPF and DKIM validation, and where to send reports to help domain owners identify dubious activity and debug issues. DMARC is also configured via a DNS TXT record:

```
$ dig +short txt _dmarc.contoso.com
"v=DMARC1; p=reject; rua=mailto:report@contoso.com; ruf=mailto:d@contoso.com;"
```

The policy value `p` tells recipients how to treat emails that fail SPF and DKIM validation. A policy of `reject`, as you guessed it, instructs recipients to discard such emails. The `rua` and `ruf` values specify emails to send two different types of diagnostic reports to.

## The Good

Regardless of SPF and DMARC configurations, you are unlikely to be able to fool robust email providers like GMail.

Google has the big data and the heuristics to provide anti-spam and anti-phishing measures that don't rely on SPF and DMARC. I briefly tried spoofing domains with lax SPF and DMARC records to a Gmail address: all emails landed in the spam box (but were not rejected).

## The Bad

If you start checking the SPF and DMARC records for a lot of organizations you'll notice weak configurations are plentiful. SPF soft fails are widespread and DMARC policies other than `reject/quarantine` are quite common.

Even `github.com` has an SPF soft fail and a `none` DMARC policy:

```
$ dig +short txt github.com
"v=spf1 ip4:192.30.252.0/22 ip4:208.74.204.0/22 ip4:46.19.168.0/23 include:_spf.google.com include:esp.github.com include:_spf.createsend.com include:mail.zendesk.com include:servers.mcsv.net ~all"
$ dig +short txt _dmarc.github.com
"v=DMARC1; p=none; rua=mailto:dmarc@github.com"
```

The reason as far as I can tell is that many companies rely on third-parties to send emails on their behalf. A typical example would be marketing emails.

SPF records can be hard to keep accurate when third parties can't provide an extensive list of IP addresses, and the ephemeral nature of many modern services means these addresses could change on a regular basis. Sharing DKIM keys with third parties may also be logistically difficult (not the mention the security implications).

Rather than risk legitimate emails getting blocked, it appears many organizations favor lax email validation rules.

Note that even when main domains, such as `contoso.com`, have SPF and DMARC adequately configured, the organization likely has other domains. What do the DNS records look like for `contoso-sales.com`?

## The Ugly

A number of organizations have SPF, DKIM and DMARC validation turned off on their inbound email filtering systems (remember that it is up to recipients to validate inbound emails). I can't give any meaningful metric as I've only sampled a negligible number in the grand scheme of things, but I've seen it enough to believe that the possibility should not be discarded by red teams and pentesters.

Reasons for having inbound validation disabled range from the good old "it's the default configuration" to an explicit desire to have email "just work". Given the amount of misconfigured DNS records out there, it is not surprising that organizations would find legitimate, if invalid, inbound emails getting blocked.

Naturally, disabled validation leaves the organizations open to some clever phishing attacks impersonating trusted external sources.

_Note that you will likely not be able to send emails from `@contoso.com` to another `@contoso.com` email address even if the SPF and DMARC records are poorly configured, and even if inbound email validation is disabled. Trying to deliver an internal email from an external source will usually fail._

## Bypassing External Filters (Sometimes)

Phishing-aware organizations will configure their inbound mail filter to tag external emails with some kind of warning to their employees. This can take the form of a subject line prefix (`Subject: "EXTERNAL: Hello World"`) or of a message added to the body of the email (`THIS MESSAGE ORIGINATES FROM OUTSIDE YOUR ORGANIZATION. BE CAREFUL.`).

Let's assume that the fictional company ACME (`acme.org`) is a subsidiary of Contoso (`contoso.com`). Given the relationship, the Sys Admins at Contoso have decided to not enforce the external filter for `acme.org`, and vice-versa. As a result emails between ACME and Contoso essentially appear as internal communications, whereas emails from other sources are tagged as external.

Unfortunately `acme.org` is configured with a DMARC policy of `none`:

```
$ dig +short txt _dmarc.acme.org
"v=DMARC1; p=none; rua=mailto:dmarc@acme.org"
```

The above DMARC configuration means recipients are not asked to enforce SPF and DKIM validation on inbound emails that claim to be from `acme.org`.

At this point, you've probably guessed it: on a recent engagement I was able to send emails to `@contoso.com` impersonating any source from `@acme.org`, _bypassing the external filter and blending in as internal communication_. This opens the door to all kinds of phishing attacks such as impersonating Sys Admins, management, HR or an automated internal system.

If we wanted to receive email responses to these phishing attempts, we could try setting the `Reply-To` header to an external email address we can read.

## `mailspoof`

[`mailspoof`](https://github.com/serain/mailspoof) is a tool I wrote to quickly scan a large list of domains for misconfigured SPF and DMARC records.

## Conclusion

If you're a red team:

* Enumerate your target's parent and subsidiary companies and their domains, as well as any external SAAS they may use.
* Identify domains with weak SPF and DMARC configurations.
* You may be able to bypass external filters by spoofing parent and subsidiary companies.
* You may be able to spoof a trusted external SAAS to harvest credentials or entice a download (note: there are legal considerations around spoofing a third-party unrelated to your engagement).

If you're an organization:

* Review your inbound email filtering solution: ensure SPF, DKIM and DMARC validation are enabled. Emails that fail validation should be quarantined.
* If you need to whitelist external domains, or treat them as internal domains, check that the domains' SPF and DMARC records are well configured so that they cannot be spoofed.
* Review your own SPF and DMARC records. You want SPF to _hard_ fail and DMARC to have a `reject` policy for both domains and subdomains.
* Ensure _all_ of your domains have SPF and DMARC configured. Even if `contoso.com` is properly configured, you don't want attackers sending emails from `contoso-sales.com`.
