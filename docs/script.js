const popover = document.querySelector("[data-popover]");
const toggle = document.querySelector("[data-popover-toggle]");

if (popover && toggle) {
  toggle.addEventListener("click", () => {
    popover.classList.toggle("is-hidden");
  });
}

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
