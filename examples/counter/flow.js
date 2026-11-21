// Reference scenario for examples/counter (built from templates/flow.js). Gate: BEFORE skipped=true, AFTER skipped=false.
// Load templates/harness.js first, then this file; run with page.__ba.run(page, 'flow', params).
async (loader) => {
  const KIND = 'flow';
  loader.__ba = { ...loader.__ba, [KIND]: async ({ page, ui }) => {
    const seen = [];
    await ui.chapter('Click +1 five times', 'Expected: 1, 2, 3, 4, 5', 2000);
    const button = page.getByRole('button', { name: '+1' });
    for (let i = 0; i < 5; i++) {
      await button.click();
      await page.waitForTimeout(600);
      seen.push(Number(await page.locator('#count').innerText()));
    }
    const skipped = seen.some((v, i) => v !== i + 1);
    await ui.banner(`Saw ${seen.join(', ')}${skipped ? ' - a number was skipped' : ''}`, 3000, skipped ? '#b91c1c' : '#15803d');
    await page.waitForTimeout(3200);
    return { seen: seen.join(','), skipped };
  } };
  return `loaded page.__ba.${KIND}`;
}
