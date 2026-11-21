// Reference scenario for examples/notes-api (built from templates/flow.js), recorded on a stage page.
// Gate: BEFORE status=200, notes 2->1, mailed=true, logged=1; AFTER status=403, notes 2->2, mailed=false, logged=0.
// (logged is the delta of log_grep around the request: the side's server log is not reset between runs.)
// Needs P.probe from scripts/probe.sh with examples/notes-api/probes.sh. Run with
// stage: 'notes-api', stageSub: 'A viewer tries to delete note 2' so the stage page is up before recording.
async (loader) => {
  const KIND = 'flow';
  loader.__ba = { ...loader.__ba, [KIND]: async ({ ui, P }) => {
    if (!P.stage) await ui.stage('notes-api', 'A viewer tries to delete note 2'); // run param missing: stage now
    await ui.chapter('1 - Starting state', 'Two notes, empty outbox', 2000);
    const before = await ui.console('note_count');
    const logBefore = await ui.console('log_grep', 'deleted note');
    await ui.chapter('2 - A viewer deletes note 2', 'Expected: 403 Forbidden, nothing changes', 2000);
    const r = await ui.request('POST', '/notes/2/delete', { headers: { 'X-Role': 'viewer' }, expect: 403 });
    await ui.chapter('3 - What changed', 'Notes, outbox and server log', 2000);
    const after = await ui.console('note_count');
    const mail = await ui.console('outbox_tail');
    const logAfter = await ui.console('log_grep', 'deleted note');
    return {
      status: r.status,
      notes: `${before.out}->${after.out}`,
      mailed: mail.out !== '(empty)',
      logged: Number(logAfter.out) - Number(logBefore.out),
    };
  } };
  return `loaded page.__ba.${KIND}`;
}
