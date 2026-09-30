const observer = new IntersectionObserver(
  (entries) => {
    for (const entry of entries) {
      if (entry.isIntersecting) {
        entry.target.classList.add("is-visible");
        observer.unobserve(entry.target);
      }
    }
  },
  { threshold: 0.45 }
);

document.querySelectorAll(".notes-visual").forEach((node) => {
  observer.observe(node);
});

document.querySelectorAll(".copy-button").forEach((button) => {
  const label = button.textContent;
  button.addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(button.dataset.copy);
      button.textContent = button.dataset.copied || label;
      setTimeout(() => {
        button.textContent = label;
      }, 1600);
    } catch {
      const code = button.parentElement.querySelector("code");
      if (code) {
        window.getSelection().selectAllChildren(code);
      }
    }
  });
});
