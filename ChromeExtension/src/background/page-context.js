/** Runs only in the explicitly invoked tab; never reads form values or page content. */
export function readPageContext() {
  return {
    url: location.href,
    pageTitle: document.title,
    language: document.documentElement.lang || navigator.language,
    viewport: { width: innerWidth, height: innerHeight, pixelRatio: devicePixelRatio },
    scroll: { x: scrollX, y: scrollY },
    browser: navigator.userAgent,
    timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
    capturedAt: new Date().toISOString()
  };
}
