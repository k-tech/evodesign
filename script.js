"use strict";

const revealItems = document.querySelectorAll(".reveal");
const revealObserver = new IntersectionObserver(
  (entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        entry.target.classList.add("is-visible");
        revealObserver.unobserve(entry.target);
      }
    });
  },
  { threshold: 0.08 },
);

revealItems.forEach((item) => revealObserver.observe(item));

const historyList = document.querySelector("[data-generation-source]");

if (historyList) {
  fetch(new URL(historyList.dataset.generationSource, document.baseURI))
    .then((response) => {
      if (!response.ok) throw new Error("Generation record unavailable");
      return response.json();
    })
    .then((record) => {
      const generation = String(record.generation).padStart(3, "0");
      const date = new Date(`${record.date}T00:00:00Z`);
      const dateLong = new Intl.DateTimeFormat("en-GB", {
        day: "numeric",
        month: "long",
        year: "numeric",
        timeZone: "UTC",
      }).format(date);

      document.querySelectorAll('[data-run-field="generation"]').forEach((item) => {
        item.textContent = generation;
      });
      document.querySelectorAll('[data-run-field="dateLong"]').forEach((item) => {
        item.textContent = dateLong;
      });
      document.querySelectorAll('[data-run-field="decision"]').forEach((item) => {
        item.textContent = record.decision;
      });
      document.querySelectorAll('[data-run-field="mainWeakness"]').forEach((item) => {
        item.textContent = record.mainWeakness;
      });
      document.querySelectorAll('[data-run-field="reason"]').forEach((item) => {
        item.textContent = record.reason;
      });

      const latestEntry = historyList.querySelector("[data-current-generation-entry]");
      const rowValues = {
        generation: `Gen ${generation}`,
        date: record.date,
        decision: record.decision,
        reason: record.reason,
      };
      Object.entries(rowValues).forEach(([field, value]) => {
        const item = latestEntry.querySelector(`[data-generation-row-field="${field}"]`);
        if (item) item.textContent = value;
      });
    })
    .catch(() => {
      // Keep the visible fallback labels when a local or hosted record cannot load.
    });
}


