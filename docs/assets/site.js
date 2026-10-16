"use strict";

(() => {
  const records = [
    {
      id: "idea",
      title: "把好想法，留在手边。",
      app: "备忘录",
      icon: "▤",
      style: "notes",
      time: "刚刚",
      type: "text",
      favorite: true,
      text: "把好想法，留在手边。\n\n不必打断思路，去找刚刚复制的那一句。\n打开历史记录，它就在这里。\n\n写作片段 / 产品灵感 / 值得留住的日常",
    },
    {
      id: "link",
      title: "developer.apple.com/design",
      app: "Safari",
      icon: "◈",
      style: "safari",
      time: "1 分钟前",
      type: "text",
      text: "https://developer.apple.com/design/\n\n设计，始于每一个小细节。\n\nApple Design Resources\n为下一个好想法，收藏一点灵感。",
    },
    {
      id: "capture",
      title: "灵感笔记 · 界面截图",
      app: "预览",
      icon: "▧",
      style: "image",
      time: "3 分钟前",
      type: "image",
      favorite: false,
      text: "一张留给下次参考的界面截图。",
      image: "assets/sample-capture.svg",
    },
    {
      id: "code",
      title: 'git commit -m "a little better"',
      app: "终端",
      icon: ">_",
      style: "terminal",
      time: "5 分钟前",
      type: "text",
      text: 'git add .\ngit commit -m "a little better"\n\n# 一次一点，让好用变得更好。',
      code: true,
    },
    {
      id: "weekend",
      title: "周末的灵感清单",
      app: "备忘录",
      icon: "▤",
      style: "notes",
      time: "10 分钟前",
      type: "text",
      favorite: true,
      text: "周末的灵感清单\n\n01  去一家没去过的书店\n02  整理桌面上散落的想法\n03  做一点没有截止日期的事\n04  留一点空白，给新的灵感",
    },
    {
      id: "color",
      title: "樱花红 · #C64063",
      app: "文本编辑",
      icon: "A",
      style: "text",
      time: "12 分钟前",
      type: "text",
      text: "樱花红\n\nHEX   #C64063\nRGB   198, 64, 99\n\n一点点强调，就刚刚好。",
    },
  ];
  const search = document.querySelector("#demo-search");
  const rows = document.querySelector("#demo-rows");
  const preview = document.querySelector("#preview-content");
  const empty = document.querySelector("#demo-empty");
  const filterButtons = Array.from(document.querySelectorAll("[data-filter]"));
  const defaultPreview = preview.cloneNode(true);
  let filter = "all";
  let selectedId = records[0].id;
  let filtered = records;
  let composing = false;
  let toastTimer;

  function notify(message) {
    const toast = document.querySelector("#demo-toast");
    clearTimeout(toastTimer);
    toast.textContent = message;
    toast.classList.add("visible");
    toastTimer = setTimeout(() => toast.classList.remove("visible"), 2600);
  }

  function showPreview(record) {
    selectedId = record?.id ?? null;
    for (const row of rows.children) {
      const selected = row.dataset.id === selectedId;
      row.classList.toggle("is-selected", selected);
      row.setAttribute("aria-pressed", String(selected));
    }
    preview.replaceChildren();
    document.querySelector("#preview-kind").textContent =
      record?.type === "image" ? "图片" : "文本";
    document.querySelector("#preview-source").textContent = record
      ? `${record.app} · ${record.time}`
      : "等待选择";
    document.querySelector("#preview-meta").textContent = record
      ? record.type === "image"
        ? "640 × 440"
        : "文本记录"
      : "";
    if (!record) {
      const message = document.createElement("p");
      message.textContent = "试试其他关键词，找回想要的片段。";
      preview.append(message);
      return;
    }
    if (record.id === "idea") {
      preview.replaceChildren(
        ...Array.from(defaultPreview.childNodes).map((node) =>
          node.cloneNode(true),
        ),
      );
    } else if (record.type === "image") {
      const label = document.createElement("p");
      label.className = "preview-kicker";
      label.textContent = "一张值得留住的参考";
      const image = document.createElement("img");
      image.className = "preview-image";
      image.src = record.image;
      image.alt = "极简风格的灵感笔记界面示例";
      image.width = 640;
      image.height = 440;
      const note = document.createElement("p");
      note.textContent = record.text;
      preview.append(label, image, note);
    } else {
      const text = document.createElement(record.code ? "pre" : "p");
      text.className = record.code ? "preview-code" : "preview-text-block";
      text.textContent = record.text;
      preview.append(text);
    }
    preview.scrollTop = 0;
  }

  function render() {
    const keyword = search.value.trim().toLocaleLowerCase();
    filtered = records.filter((record) => {
      const matchesType =
        filter === "all" ||
        (filter === "favorite" ? record.favorite : record.type === filter);
      return (
        matchesType &&
        `${record.title} ${record.text} ${record.app}`
          .toLocaleLowerCase()
          .includes(keyword)
      );
    });
    rows.replaceChildren();
    for (const record of filtered) {
      const row = document.createElement("button");
      row.type = "button";
      row.className = "demo-row";
      row.dataset.id = record.id;
      row.setAttribute(
        "aria-label",
        `${record.title}，来自${record.app}，${record.time}`,
      );
      const icon = document.createElement("span");
      icon.className = `source-icon source-${record.style}`;
      icon.textContent = record.icon;
      icon.setAttribute("aria-hidden", "true");
      const title = document.createElement("span");
      title.className = "row-title";
      title.textContent = record.title;
      const time = document.createElement("span");
      time.className = "row-time";
      time.textContent = record.time;
      row.append(icon, title, time);
      if (record.favorite) {
        const star = document.createElement("span");
        star.className = "row-star";
        star.textContent = "☆";
        star.setAttribute("aria-hidden", "true");
        row.append(star);
      }
      row.addEventListener("pointerenter", (event) => {
        if (event.pointerType !== "touch") showPreview(record);
      });
      row.addEventListener("focus", () => showPreview(record));
      row.addEventListener("click", () => showPreview(record));
      rows.append(row);
    }
    empty.hidden = filtered.length !== 0;
    rows.hidden = filtered.length === 0;
    document.querySelector("#result-count").textContent =
      `${filtered.length} 条记录`;
    showPreview(
      filtered.find((record) => record.id === selectedId) ?? filtered[0],
    );
  }

  search.addEventListener("compositionstart", () => {
    composing = true;
  });
  search.addEventListener("compositionend", () => {
    composing = false;
    render();
  });
  search.addEventListener("input", () => {
    if (!composing) render();
  });
  filterButtons.forEach((button) =>
    button.addEventListener("click", () => {
      filter = button.dataset.filter;
      filterButtons.forEach((item) => {
        item.classList.toggle("is-active", item === button);
        item.setAttribute("aria-pressed", String(item === button));
      });
      render();
    }),
  );
  document
    .querySelector(".clipboard-window")
    .addEventListener("keydown", (event) => {
      if (composing || event.isComposing) return;
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "f") {
        event.preventDefault();
        search.focus();
      } else if (event.key === "Escape" && search.value) {
        event.preventDefault();
        search.value = "";
        render();
      } else if (
        ["ArrowDown", "ArrowUp"].includes(event.key) &&
        filtered.length
      ) {
        event.preventDefault();
        const index = filtered.findIndex((record) => record.id === selectedId);
        const next = Math.max(
          0,
          Math.min(
            filtered.length - 1,
            index + (event.key === "ArrowDown" ? 1 : -1),
          ),
        );
        showPreview(filtered[next]);
        rows.children[next]?.scrollIntoView({
          block: "nearest",
          behavior: "instant",
        });
      } else if (
        event.key === "Enter" &&
        selectedId &&
        !event.target.closest("[data-filter]")
      ) {
        event.preventDefault();
        notify("这是网页演示，未修改你的系统剪贴板。下载 Mac 版体验复制。");
      }
    });
  document
    .querySelector("#try-search")
    .addEventListener("click", () => search.focus({ preventScroll: true }));

  document
    .querySelector("#copy-install")
    .addEventListener("click", async (event) => {
      const button = event.currentTarget;
      const status = document.querySelector("#copy-status");
      button.disabled = true;
      try {
        if (!navigator.clipboard?.writeText)
          throw new Error("Clipboard API unavailable");
        await navigator.clipboard.writeText(
          document.querySelector("#install-command").textContent.trim(),
        );
        status.textContent = "安装命令已复制。";
      } catch {
        const selection = window.getSelection();
        const range = document.createRange();
        range.selectNodeContents(document.querySelector("#install-command"));
        selection.removeAllRanges();
        selection.addRange(range);
        status.textContent = "命令已选中，请按 ⌘C 或 Ctrl+C 复制。";
      } finally {
        button.disabled = false;
      }
    });

  render();
  if (
    "IntersectionObserver" in window &&
    !window.matchMedia("(prefers-reduced-motion: reduce)").matches
  ) {
    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          entry.target.classList.remove("is-pending");
          entry.target.classList.add("is-visible");
          observer.unobserve(entry.target);
        });
      },
      { threshold: 0.08 },
    );
    document.querySelectorAll(".reveal").forEach((element) => {
      element.classList.add("is-pending");
      observer.observe(element);
    });
  }
})();
