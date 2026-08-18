const express = require("express");
const fs = require("fs");

const app = express();

app.get("/download", (req, res) => {
  const filename = req.query.filename;
  const content = fs.readFileSync(filename, "utf8");
  res.send(content);
});

app.listen(3000);
