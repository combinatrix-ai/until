const observer = new IntersectionObserver(
  (entries) => {
    for (const entry of entries) {
      if (entry.isIntersecting) {
        entry.target.classList.add("is-visible");
      }
    }
  },
  { threshold: 0.18 }
);

document.querySelectorAll(".workflow-grid article").forEach((node) => {
  observer.observe(node);
});
