---
title: "{{ category.name }}"
hide:
  - toc
---

# 📅 {{ category.name }} 문서

## 최근 문서 목록

{% for post in page.posts %}
- [{{ post.title }}]({{ post.url }})
{% endfor %}

{% if page.next_page %}
👉 [다음 →]({{ page.next_page.url }})
{% endif %}

---

## 📝 가장 최근 문서 본문

{% if page.posts %}
{{ page.posts[0].content }}
{% endif %}
