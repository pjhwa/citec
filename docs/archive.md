---
layout: page
title: Archive
---

{% for post in site.posts %}
  {% assign current_year = post.date | date: "%Y" %}
  {% assign current_month = post.date | date: "%B" %}
  {% if current_year != year or current_month != month %}
    {% assign year = current_year %}
    {% assign month = current_month %}
    <h2><a href="/archive/{{ year }}/{{ month | downcase }}">{{ year }} - {{ month }}</a></h2>
  {% endif %}
{% endfor %}
