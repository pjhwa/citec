---
title: "2025년 4월"
hide:
  - toc
---

{% if page.posts %}
## 최근 문서 목록

{% for post in page.posts %}
- [{{ post.title }}]({{ post.url }})
{% endfor %}

{% if page.next_page %}
👉 [다음 →]({{ page.next_page.url }})
{% endif %}

---

## 가장 최근 문서 보기

{{ page.posts[0].content }}
{% endif %}
