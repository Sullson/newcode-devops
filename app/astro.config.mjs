// @ts-check
import { defineConfig } from 'astro/config';

// Static output: identical artifact ships to Azure Static Web Apps AND the
// nginx container deployed on AKS — one build, two delivery paths.
export default defineConfig({
  site: 'https://newcode.msulawiak.pl',
  output: 'static',
  // No client JS framework, no telemetry, no external fonts — privacy by default.
  trailingSlash: 'ignore',
  build: {
    inlineStylesheets: 'auto',
  },
});
