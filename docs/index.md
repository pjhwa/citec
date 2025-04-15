---
title: "Grok 문서 모음"
hide:
  - navigation
  - toc
---

# 🗂️ 최신 문서 보기

## 📅 월별 문서

{% set month = config.extra.blog.date | date(format="%Y-%m") %}

{% for post in blog.posts | selectattr("date", "string", month) | reverse[:5] %}
- [{{ post.title }}]({{ post.url }})
{% endfor %}

---

## 📝 이달의 첫 문서

{% if blog.posts %}
{{ blog.posts[-1].content }}
{% endif %}
