# Problem Understanding 

## Problems (P1 to P8)

### P1: "Near me" and "open now" searches
* **Business Need:** The search system must quickly return nearby open places based on current coordinates and operating hours, including venues that stay open past midnight, so users get instant recommendations without delays.
* **Stakeholders Affected:** Traveller / driver, business owner, search team.
* **Classification:** Customer-facing / real-time.

### P2: Place pages and "Saved" tab
* **Business Need:** When a user opens a place profile or their saved lists, the app must immediately show place details, weekday opening hours, recent reviews, and bookmarked places to ensure a smooth user experience.
* **Stakeholders Affected:** Traveller / driver, business owner.
* **Classification:** Customer-facing / real-time.

### P3: Live traffic and incident overlays
* **Business Need:** The navigation map needs fresh traffic congestion levels and reported road hazards (like waterlogging, accidents, and police checks) updated every minute so drivers receive timely warnings.
* **Stakeholders Affected:** Traveller / driver, traffic team.
* **Classification:** Customer-facing / real-time.

### P4: "Typical traffic" charts and road safety
* **Business Need:** Traffic engineers need to analyze hourly speed patterns on road segments and assess how often vehicles exceed speed limits to plan road improvements and speed limit enforcement.
* **Stakeholders Affected:** Traffic team.
* **Classification:** Reporting / analytics.

### P5: Navigation start and routing quality
* **Business Need:** Starting a journey must be instant for the user, while the routing team needs periodic reports on ETA calculation accuracy and destinations with frequent rerouting to tune the routing engine.
* **Stakeholders Affected:** Traveller / driver, routing & ETA team.
* **Classification:** 
  * Starting navigation: Customer-facing / real-time.
  * ETA accuracy and rerouting analysis: Reporting / analytics.

### P6: Unused starting points
* **Business Need:** The data team needs a reliable list of places that have never been used as a journey starting point to clean up the places catalog and identify inactive listings.
* **Stakeholders Affected:** Data-quality team.
* **Classification:** Reporting / analytics.

### P7: Data quality checks
* **Business Need:** Automated audits must regularly check for mismatched ratings, closed places still receiving navigation requests, places with missing hours, and duplicate nearby listings to keep the database accurate.
* **Stakeholders Affected:** Business owner, Local Guide, data-quality team.
* **Classification:** Reporting / analytics.

### P8: Leaderboards, moderation, and growth reports
* **Business Need:** The community and moderation teams need to rank active Local Guides, review newly flagged content across deep pages, and monitor health-sector navigation trends to support community growth.
* **Stakeholders Affected:** Local Guide, moderation, routing & ETA team.
* **Classification:** Reporting / analytics.

---

## Assumptions

1. **Journey Origins:** A navigation session may start directly from GPS coordinates instead of a registered place, so `origin_place_id` can be NULL.
2. **Anonymous Sessions:** Some navigation sessions may not be linked to a registered user, so `user_id` can also be NULL.
3. **Midnight Hours:** If closing time is earlier than opening time (e.g. 18:00 to 02:00), the place operates past midnight and closes the following day.
4. **Ratings and Reviews:** A place with no reviews has a NULL average rating and a review count of 0.
5. **Saved Lists:** A user may save the same place in different lists. Each saved entry is uniquely identified by the composite key of `user_id`, `place_id`, and `list_name`.
6. **Coordinates:** Coordinates are stored as decimal latitude and longitude values for locations in India. Distances are measured in kilometers using standard spherical Earth calculations.