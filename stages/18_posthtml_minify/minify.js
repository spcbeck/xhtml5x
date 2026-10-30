#!/usr/bin/env node

/**
 * Stage 18: PostHTML / HTML minifier
 * Ingests XHTML document, parses AST through PostHTML, extracts the canonical
 * payload node, normalizes whitespace, and outputs clean HTML5.
 */

const fs = require('fs');
const posthtml = require('posthtml');
const { render } = require('posthtml-render');

function normalizeAstWhitespace(node) {
  if (typeof node === 'string') {
    return node.replace(/^\n+|\n+$/g, '');
  }
  if (node && Array.isArray(node.content)) {
    node.content = node.content
      .map(normalizeAstWhitespace)
      .filter((child) => !(typeof child === 'string' && child.length === 0));
  }
  return node;
}

function main() {
  const inputFile = process.argv[2] || 'output.xhtml';
  const outputFile = process.argv[3] || 'output.html';

  const xhtml = fs.readFileSync(inputFile, 'utf8');

  let articleNode = null;
  posthtml([
    (tree) => {
      tree.match({ tag: 'article' }, (node) => {
        articleNode = normalizeAstWhitespace(node);
        return node;
      });
    }
  ]).process(xhtml, { sync: true });

  if (!articleNode) {
    console.error('PostHTML failed to locate <article> node in AST');
    process.exit(1);
  }

  // Render HTML5 string from PostHTML AST
  const html5 = render(articleNode).trim();

  fs.writeFileSync(outputFile, html5 + '\n', 'utf8');
  console.log(`[Stage 18] PostHTML transformed & emitted HTML5 -> ${outputFile}`);
}

main();
