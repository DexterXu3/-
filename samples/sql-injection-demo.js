const express = require("express");
const mysql = require("mysql2");

const app = express();

app.get("/users", (req, res) => {
  const username = req.query.username;
  const sql = "SELECT * FROM users WHERE username = '" + username + "'";

  mysql.query(sql, (error, rows) => {
    if (error) {
      return res.status(500).json({ error: "Query failed" });
    }
    res.json(rows);
  });
});

app.listen(3000);
