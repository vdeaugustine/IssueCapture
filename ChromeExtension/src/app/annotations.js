/** Loads an evidence image without changing its original bytes. */
export async function loadImage(source) {
  const image = new Image();
  image.src = source;
  await image.decode();
  return image;
}

function drawPath(context, annotation, width, height) {
  const points = annotation.points.map(point => ({ x: point.x * width, y: point.y * height }));
  if (points.length < 2) return;
  const first = points[0];
  const last = points.at(-1);
  context.beginPath();
  if (annotation.tool === 'rectangle') {
    context.rect(first.x, first.y, last.x - first.x, last.y - first.y);
  } else {
    context.moveTo(first.x, first.y);
    for (const point of points.slice(1)) context.lineTo(point.x, point.y);
    if (annotation.tool === 'arrow') {
      const angle = Math.atan2(last.y - first.y, last.x - first.x);
      const length = width * .018;
      for (const direction of [-1, 1]) {
        context.moveTo(last.x, last.y);
        context.lineTo(last.x - length * Math.cos(angle + direction * .5), last.y - length * Math.sin(angle + direction * .5));
      }
    }
  }
  context.stroke();
}

/** Renders normalized annotations; original screenshot storage stays immutable. */
export function paintEvidence(canvas, image, annotations) {
  canvas.width = image.naturalWidth;
  canvas.height = image.naturalHeight;
  const context = canvas.getContext('2d');
  context.drawImage(image, 0, 0);
  context.lineCap = 'round';
  context.lineJoin = 'round';
  for (const annotation of annotations) {
    context.strokeStyle = '#151515';
    context.lineWidth = Math.max(5, canvas.width * .005);
    drawPath(context, annotation, canvas.width, canvas.height);
    context.strokeStyle = '#ffffff';
    context.lineWidth = Math.max(2, canvas.width * .0025);
    drawPath(context, annotation, canvas.width, canvas.height);
  }
}

/** Connects pointer annotation tools to a responsive screenshot canvas. */
export async function createAnnotator(canvas, screenshot, annotations, onChange) {
  const image = await loadImage(screenshot);
  let tool = 'arrow';
  let current = null;
  const redraw = () => paintEvidence(canvas, image, current ? [...annotations, current] : annotations);
  const point = event => {
    const bounds = canvas.getBoundingClientRect();
    return { x: Math.max(0, Math.min(1, (event.clientX - bounds.left) / bounds.width)),
      y: Math.max(0, Math.min(1, (event.clientY - bounds.top) / bounds.height)) };
  };
  canvas.onpointerdown = event => {
    if (event.button !== 0) return;
    current = { tool, points: [point(event)] };
    canvas.setPointerCapture(event.pointerId);
  };
  canvas.onpointermove = event => {
    if (!current) return;
    if (tool === 'pen' || current.points.length === 1) current.points.push(point(event));
    else current.points[1] = point(event);
    redraw();
  };
  canvas.onpointerup = event => {
    if (!current) return;
    current.points.push(point(event));
    annotations.push(current);
    current = null;
    redraw();
    onChange();
  };
  canvas.onpointercancel = () => { current = null; redraw(); };
  redraw();
  return {
    setTool(value) { tool = value; },
    undo() { annotations.pop(); redraw(); onChange(); }
  };
}

/** Produces a separate annotated PNG for an export. */
export async function annotatedImage(issue) {
  const canvas = document.createElement('canvas');
  paintEvidence(canvas, await loadImage(issue.screenshot), issue.annotations);
  return canvas.toDataURL('image/png');
}
