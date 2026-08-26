---
layout: post
title: "Captioning images for retrieval: frontier vs 8B"
date: 2026-08-20T11:00:00+00:00
author: alxk
sitemap: false
keywords: "ai rag vlm embeddings retrieval"
description: "Is a frontier multimodal model worth it over a small VLM for captioning photos in a RAG pipeline? Benchmarking Opus 5, Qwen3-VL-8B and Ministral on MS COCO retrieval."
---

# Captioning images for retrieval: frontier vs 8B

TL;DR I wanted to know if there was any substantial difference between a frontier model and a small VLM for simple captioning of photos in a RAG pipeline. The answer is no, confirming priors.

The experiment was conducted end to end with Claude Code in ~30 minutes, with human steering. This blog post was written entirely by the human in question (me).

## Introduction

There are different ways to support image lookups in RAG pipelines, and I wanted to play with the more pedestrian one: caption the images using a VLM and pipe that through an embedding model. This is the "collapse everything into text" approach and it works well enough to pull images of dogs or plants out of your personal photo album. For more serious applications ("what was growth in Q3 2025?" in charts in ingested PDFs) I'd look at ColPali/ColQwen or structured extraction approaches.

Specifically I wanted to figure out if frontier multimodal models (expensive) offered any advantage over small VLMs (cheap) for my personal photo retrieval needs. My prior was no, but I had time to kill so I fired up Claude Code.

## Approach

We took the MS COCO dataset and used a fixed 1000 images of the `val` split. Big warning: all models have likely seen COCO in training, so this will need validation on our own dataset.

MS COCO images come with 5 human-written captions per image. We reserved the first human-written caption of each image to embed and put in the index, to serve as a human baseline for captioning.

The other 4 human-written captions were used as queries to test retrieval.

We generated captions for the images using the following models:

* Claude Opus 5 (`claude-opus-5`)
* Qwen3-VL-8B-Instruct (`qwen/qwen3-vl-8b-instruct`)
* Ministral 8B (`mistralai/ministral-8b-2512`)
* Ministral 3B (`mistralai/ministral-3b-2512`)

and the following two prompts:

```
PROMPT_0 = (
    "Describe this image for a search index. State the main objects, their notable "
    "attributes, what is happening, and the setting. Be concrete and factual. "
    "Do not speculate. Write one sentence."
)
PROMPT_BARE = "Describe this image. Write one sentence."
```

We used `bge-base-en-v1.5@a5beb1e3` to generate embeddings and then took the cosine similarity between model-generated captions and the queries.

We measured costs, mean tokens in captions, recall@1, recall@3 and MRR.

We also built a shuffled control as a sanity check: each image was assigned a caption embedding from another image. We expected near 0 recall and MRR on queries here.

## Results & Discussion

![Forest plot of paired differences in recall@1 with 95% confidence intervals](https://alex.kaskaso.li/images/posts/vlm-captioning-retrieval/forest.svg)

For recall@1, no significant difference between Opus 5 and Qwen3-VL-8B on `PROMPT_0`. On the bare prompt Opus 5 is ahead by a small but significant margin.

Ministral 8B and 3B perform roughly the same, and Qwen3-VL-8B beats Ministral 8B in the 8B category.

| Model | Prompt | mean tokens | recall@1 | recall@3 | MRR | $ / 1k images |
|---|---|---|---|---|---|---|
| Opus 5 | bare | 38.4 | 0.573 ±0.021 | 0.764 ±0.017 | 0.688 ±0.017 | $3.535 |
| Qwen3-VL-8B | prompt-0 | 39.7 | 0.561 ±0.022 | 0.752 ±0.018 | 0.678 ±0.017 | $0.055 |
| Opus 5 | prompt-0 | 66.0 | 0.559 ±0.021 | 0.747 ±0.018 | 0.676 ±0.016 | $4.793 |
| Qwen3-VL-8B | bare | 29.3 | 0.550 ±0.021 | 0.742 ±0.018 | 0.668 ±0.016 | $0.047 |
| Ministral 3B | bare | 30.3 | 0.515 ±0.022 | 0.716 ±0.020 | 0.639 ±0.017 | $0.043 |
| Ministral 8B | prompt-0 | 50.6 | 0.510 ±0.022 | 0.726 ±0.021 | 0.641 ±0.019 | $0.072 |
| Ministral 3B | prompt-0 | 47.2 | 0.509 ±0.022 | 0.717 ±0.020 | 0.638 ±0.017 | $0.048 |
| Ministral 8B | bare | 26.7 | 0.502 ±0.021 | 0.704 ±0.019 | 0.629 ±0.017 | $0.064 |
| human caption #1 | — | 12.0 | 0.429 ±0.021 | 0.625 ±0.022 | 0.559 ±0.018 | — |
| shuffled control | — | 12.0 | 0.000 ±0.000 | 0.001 ±0.001 | 0.006 ±0.001 | — |
{: .scroll}

± is half a 95% bootstrap confidence interval.

`PROMPT_0` induces slightly longer captions which appear to correlate marginally positively with performance for Qwen3-VL-8B, although we're within error margins.

The human caption performs poorly here, perhaps because the mean token length is not sufficient to carry detail about an image.

Interestingly, the longer captions induced by Opus 5 with `PROMPT_0` cost ~36% more for no significant gain. Note though that we didn't use batch inference for this test.

## Conclusion

`Qwen3-VL-8B` performs similarly to Opus 5 on this task and is cheap.
