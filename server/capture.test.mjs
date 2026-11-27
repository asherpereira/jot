import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {calendar, validDraft, validInput, parseCapture} from './capture.mjs';
const example = JSON.parse(readFileSync(new URL('../contracts/friday.example.json', import.meta.url)));
const input = {text: 'yo i have maths homework due this friday maybe it will take an hour could u also remind me to upload all my work afterwards', localDate: '2026-11-25'};

test('Friday capture travels through the Gemini response envelope', async () => {
  const draft = await parseCapture(input, {key: 'test-key', model: 'test', fetchImpl: async (_, options) => {
    const request = JSON.parse(options.body);
    assert.equal(request.generationConfig.responseMimeType, 'application/json');
    assert.ok(request.generationConfig.responseJsonSchema.required.includes('afterCompletion'));
    assert.ok(JSON.parse(request.contents[0].parts[0].text).calendar.includes('2026-11-27 Friday'));
    return Response.json({candidates: [{finishReason: 'STOP', content: {parts: [{text: JSON.stringify(example)}]}}]});
  }});
  assert.deepEqual(draft, example);
});
test('invalid dates, detached times, oversized estimates and extra fields fail', () => {
  assert.ok(validInput(input));
  assert.ok(!validInput({...input, localDate: '2026-02-30'}));
  for (const changes of [{dueDate:'2026-02-30'}, {dueTime:'17:00', dueDate:null}, {estimateMinutes:300}, {subject:'  '}, {deleteAll:true}]) {
    assert.ok(!validDraft({...example, ...changes}));
  }
  assert.equal(calendar('2026-12-31')[1], '2027-01-01 Friday');
});

test('draft length limits count Unicode code points', () => {
  assert.ok(validDraft({...example, title: '📚'.repeat(160)}));
  assert.ok(!validDraft({...example, title: '📚'.repeat(161)}));
});
