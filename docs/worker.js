// Runs the ERCAudit analyzer (pure Python) inside the browser with Pyodide. Nothing is sent to a server.
importScripts("https://cdn.jsdelivr.net/pyodide/v0.26.4/full/pyodide.js");

const ready = (async () => {
  const py = await loadPyodide();
  const files = await (await fetch("app/files.json")).json();
  for (const f of files) {
    const text = await (await fetch("app/" + f)).text();
    const dir = "/home/pyodide/" + f.substring(0, f.lastIndexOf("/"));
    py.FS.mkdirTree(dir);
    py.FS.writeFile("/home/pyodide/" + f, text);
  }
  py.runPython("import sys, json\nsys.path.insert(0, '/home/pyodide')\nimport ercaudit.webcore as w");
  return py;
})();

onmessage = async (e) => {
  try {
    const py = await ready;
    py.globals.set("SRC", e.data.source);
    const out = py.runPython("json.dumps(w.audit_text(SRC))");
    postMessage({id: e.data.id, result: JSON.parse(out)});
  } catch (err) {
    postMessage({id: e.data.id, error: String(err).split("\n").slice(-8).join(" | ")});
  }
};
