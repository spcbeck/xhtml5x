#!/usr/bin/env node

/**
 * Stage 16: HTMX fragment (hx-get) executed in an ephemeral headless Node DOM harness.
 */

const fs = require('fs');
const path = require('path');
const { JSDOM } = require('jsdom');

function main() {
  const inputFile = process.argv[2] || 'output.html';
  const outputFile = process.argv[3] || 'resolved_dom.html';

  // 1. Ingest rendered HTML payload from Stage 15 (Handlebars)
  const renderedPayload = fs.readFileSync(inputFile, 'utf8').trim();

  // 2. Headless DOM host document defining the HTMX dynamic fragment
  const hostHtml = `<!DOCTYPE html>
<html>
<body>
  <main id="app">
    <div id="target" hx-get="/article" hx-trigger="load" hx-swap="outerHTML settle:0ms">
      <!-- Ephemeral HTMX placeholder -->
    </div>
  </main>
</body>
</html>`;

  const dom = new JSDOM(hostHtml, {
    runScripts: 'dangerously',
    url: 'http://localhost/'
  });
  const doc = dom.window.document;

  // JSDOM requires explicit XPath result type argument; browser spec defaults to 0 (ANY_TYPE)
  const origExprEval = dom.window.XPathExpression.prototype.evaluate;
  dom.window.XPathExpression.prototype.evaluate = function (ctx, type = 0, res = null) {
    return origExprEval.call(this, ctx, type, res);
  };

  // Wire up synchronous in-memory XMLHttpRequest responder for HTMX
  dom.window.XMLHttpRequest = class {
    constructor() {
      this.upload = { addEventListener() {} };
    }
    addEventListener() {}
    open(method, url) {
      this.method = method;
      this.url = url;
    }
    setRequestHeader() {}
    overrideMimeType() {}
    getAllResponseHeaders() {
      return '';
    }
    getResponseHeader() {
      return null;
    }
    send() {
      if (this.url === '/article') {
        this.status = 200;
        this.responseText = renderedPayload;
        this.response = renderedPayload;
      } else {
        this.status = 404;
        this.responseText = '';
        this.response = '';
      }
      if (typeof this.onload === 'function') {
        this.onload();
      }
    }
  };

  // 3. Listen for HTMX lifecycle completion and execute actual htmx.org runtime inside JSDOM
  doc.body.addEventListener('htmx:afterSettle', () => {
    const resolvedArticle = doc.querySelector('article');
    if (!resolvedArticle) {
      console.error('Failed to resolve article element in DOM after HTMX swap');
      process.exit(1);
    }

    // JSDOM leaves an empty class="" attribute after classList.remove('htmx-added', 'htmx-settling')
    if (resolvedArticle.getAttribute('class') === '') {
      resolvedArticle.removeAttribute('class');
    }

    fs.writeFileSync(outputFile, resolvedArticle.outerHTML + '\n', 'utf8');
    console.log(`[Stage 16] HTMX v${dom.window.htmx.version} swapped & settled fragment in headless DOM -> ${outputFile}`);
  });

  const htmxPath = path.join(path.dirname(require.resolve('htmx.org')), 'htmx.js');
  const htmxCode = fs.readFileSync(htmxPath, 'utf8');
  dom.window.eval(htmxCode);
}

main();
