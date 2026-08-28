$(document).ready(function () {
  const field = document.getElementById('thesis_abstract');
  const panel = document.getElementById('abstract-preview');
  if (!field || !panel) return;

  const preview = document.getElementById('abstract-paragraph-preview');
  const emptyMessage = document.getElementById('abstract-preview-empty');

  function updatePreview() {
    // Normalize only the preview. Never rewrite the student's textarea value.
    const text = field.value.replace(/\r\n?/g, '\n').trim();
    const paragraphs = text ? text.split(/\n[ \t]*\n(?:[ \t]*\n)*/) : [];
    preview.replaceChildren();

    paragraphs.forEach(function (paragraph) {
      const element = document.createElement('p');
      element.textContent = paragraph.replace(/\n/g, ' ').trim();
      preview.appendChild(element);
    });

    emptyMessage.hidden = paragraphs.length > 0;
  }

  field.addEventListener('input', updatePreview);
  updatePreview();
  panel.hidden = false;
});
