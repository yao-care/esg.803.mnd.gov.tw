const fs = require('fs');
const path = require('path');
const { PROJECT_ROOT } = require('./config.js');

const DB_PATH = path.join(PROJECT_ROOT, 'tracking.db');

function getDb() {
  // better-sqlite3 is an optional dependency
  try {
    const Database = require('better-sqlite3');
    return new Database(DB_PATH);
  } catch {
    return null;
  }
}

function initDb() {
  const db = getDb();
  if (!db) {
    console.warn('tracking.db: better-sqlite3 not installed. Tracking disabled.');
    return;
  }

  db.exec(`
    CREATE TABLE IF NOT EXISTS collection_runs (
      run_id TEXT PRIMARY KEY,
      collector TEXT NOT NULL,
      target TEXT,
      depth TEXT,
      status TEXT NOT NULL,
      timestamp TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS drill_records (
      drill_id TEXT PRIMARY KEY,
      type TEXT NOT NULL,
      status TEXT NOT NULL,
      scheduled_at TEXT,
      completed_at TEXT
    );

    CREATE TABLE IF NOT EXISTS qa_scores (
      report_date TEXT PRIMARY KEY,
      search_hit_rate REAL,
      answer_rate REAL,
      citation_accuracy REAL
    );

    CREATE TABLE IF NOT EXISTS findings (
      finding_id TEXT PRIMARY KEY,
      source TEXT,
      severity TEXT,
      status TEXT DEFAULT 'open',
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      resolved_at TEXT
    );
  `);

  db.close();
}

// Record a collection run
function recordCollectionRun(runId, collector, target, depth, status) {
  const db = getDb();
  if (!db) return;
  db.prepare('INSERT OR REPLACE INTO collection_runs (run_id, collector, target, depth, status) VALUES (?, ?, ?, ?, ?)')
    .run(runId, collector, target, depth, status);
  db.close();
}

// Record QA scores
function recordQaScores(reportDate, searchHitRate, answerRate, citationAccuracy) {
  const db = getDb();
  if (!db) return;
  db.prepare('INSERT OR REPLACE INTO qa_scores (report_date, search_hit_rate, answer_rate, citation_accuracy) VALUES (?, ?, ?, ?)')
    .run(reportDate, searchHitRate, answerRate, citationAccuracy);
  db.close();
}

module.exports = { getDb, initDb, recordCollectionRun, recordQaScores, DB_PATH };
