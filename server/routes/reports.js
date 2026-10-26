/** routes/reports.js — role-scoped reports registry. Quantities & weights only. */
const express = require('express');
const db = require('../db');
const { requirePerm, bad } = require('../middleware');
const { audit } = require('../helpers');
const { xlsxBuffer } = require('../xlsx');

const router = express.Router();

const DAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

const REPORTS = {
  'inventory-valuation': {
    title: 'Inventory Stock Report',
    desc: 'Stock on hand per finished good (cartons, trays, bottles, weight).',
    run: () => ({
      columns: ['Product', 'Cartons', 'Trays', 'Total Bottles', 'Gross kg'],
      rows: db.prepare(
        `SELECT p.name, i.qty_cb, i.qty_trays,
                i.qty_cb * p.bottles_per_cb + i.qty_trays * p.bottles_per_tray bottles,
                ROUND(i.qty_cb * p.weight_per_cb + i.qty_trays * p.tray_weight, 2) kg
         FROM inventory i JOIN products p ON p.id = i.product_id WHERE p.active = 1 ORDER BY p.sort_order, p.name`
      ).all().map((r) => [r.name, r.qty_cb, r.qty_trays, r.bottles, r.kg]),
    }),
  },
  'low-stock': {
    title: 'Low Stock Report',
    desc: 'Products below their minimum stock level.',
    run: () => ({
      columns: ['Product', 'In Stock (CB)', 'Minimum (CB)', 'Shortfall (CB)', 'Trays'],
      rows: db.prepare(
        `SELECT p.name, i.qty_cb, p.min_stock_cb, p.min_stock_cb - i.qty_cb short, i.qty_trays
         FROM inventory i JOIN products p ON p.id = i.product_id
         WHERE i.qty_cb < p.min_stock_cb AND p.active = 1 ORDER BY short DESC`
      ).all().map((r) => [r.name, r.qty_cb, r.min_stock_cb, r.short, r.qty_trays]),
    }),
  },
  'production-output': {
    title: 'Production Output Register',
    desc: 'Batches with planned vs produced quantities.',
    run: () => ({
      columns: ['Batch', 'Product', 'Planned CB', 'Produced CB', 'Trays', 'Variance', 'Status', 'Completed On'],
      rows: db.prepare(
        `SELECT b.code, p.name, b.planned_cb, b.produced_cb, b.produced_trays,
                b.produced_cb - b.planned_cb var, b.status,
                COALESCE(date(b.completed_at), '—') done
         FROM batches b JOIN products p ON p.id = b.product_id ORDER BY b.created_at DESC LIMIT 100`
      ).all().map((r) => [r.code, r.name, r.planned_cb, r.produced_cb, r.produced_trays, r.var, r.status, r.done]),
    }),
  },
  'batch-stock': {
    title: 'Batch-wise Stock',
    desc: 'Remaining stock per production batch, grouped by product — dispatched quantities already deducted. "Unassigned" = stock on hand that no batch accounts for (opening stock / manual adjustments). Every TOTAL equals Stock on Hand.',
    run: () => require('../batchrecon').batchStockRows(db), /* ffBatchRecon */
  },
  'dispatch-register': {
    title: 'Dispatch Register',
    desc: 'Every truck dispatched — destination, quantities and weights.',
    run: () => ({
      columns: ['Code', 'Date', 'Day', 'Truck', 'Destination', 'Batch Codes', 'Cartons', 'Trays', 'Bottles', 'Gross kg'],
      rows: db.prepare(
        `SELECT code, date(dispatch_date) d, cast(strftime('%w', dispatch_date) as integer) wd,
                truck_number, destination,
                REPLACE((SELECT GROUP_CONCAT(DISTINCT di.batch_code) FROM dispatch_items di WHERE di.dispatch_id = dispatches.id AND di.batch_code IS NOT NULL AND di.batch_code != ''), ',', char(10)) batch_codes,
                total_cartons, total_trays, total_bottles, gross_weight
         FROM dispatches ORDER BY created_at DESC LIMIT 200`
      ).all().map((r) => [r.code, r.d, DAYS[r.wd] || '', r.truck_number, r.destination || '—', r.batch_codes || '—', r.total_cartons, r.total_trays, r.total_bottles, r.gross_weight]),
    }),
  },
  'adjustment-register': {
    title: 'Stock Adjustment Register',
    desc: 'All adjustment requests with their approval status.',
    run: () => ({
      columns: ['Code', 'Product', 'Type', 'CB', 'Reason', 'Status', 'Requested By', 'Decided By', 'Decided On'],
      rows: db.prepare(
        `SELECT a.code, p.name, a.adj_type, a.qty_cb, a.reason, a.status,
                ru.name req, COALESCE(au.name, ju.name, '—') dec,
                COALESCE(a.approved_at, a.rejected_at, '—') dt
         FROM adjustments a
         JOIN products p ON p.id = a.product_id
         JOIN users ru ON ru.id = a.requested_by
         LEFT JOIN users au ON au.id = a.approved_by
         LEFT JOIN users ju ON ju.id = a.rejected_by
         ORDER BY a.requested_at DESC LIMIT 200`
      ).all().map((r) => [r.code, r.name, r.adj_type, r.qty_cb, r.reason, r.status, r.req, r.dec, r.dt]),
    }),
  },
  'approval-audit': {
    title: 'Approval Audit Trail',
    desc: 'Who approved or rejected what, and when.',
    run: () => ({
      columns: ['Code', 'Product', 'Decision', 'By', 'On', 'Reason / Remarks'],
      rows: db.prepare(
        `SELECT a.code, p.name, a.status, COALESCE(au.name, ju.name) who,
                COALESCE(a.approved_at, a.rejected_at) dt,
                TRIM(COALESCE(a.reject_reason, '') || ' ' || COALESCE(a.approval_remarks, '')) note
         FROM adjustments a
         JOIN products p ON p.id = a.product_id
         LEFT JOIN users au ON au.id = a.approved_by
         LEFT JOIN users ju ON ju.id = a.rejected_by
         WHERE a.status != 'PENDING'
         ORDER BY dt DESC LIMIT 200`
      ).all().map((r) => [r.code, r.name, r.status, r.who, r.dt, r.note || '—']),
    }),
  },
  'packing-stock': {
    title: 'Packing Material Stock',
    desc: 'Current balance of every packing material.',
    run: () => ({
      columns: ['Material', 'Category', 'Unit', 'Balance', 'Minimum', 'Status'],
      rows: db.prepare(
        `SELECT name, category, unit, stock, min_stock,
                CASE WHEN stock < min_stock THEN 'LOW' ELSE 'OK' END st
         FROM packing_materials WHERE category <> 'Raw Material' ORDER BY category, name`
      ).all().map((r) => [r.name, r.category, r.unit, r.stock, r.min_stock, r.st]),
    }),
  },
  'raw-material-stock': {
    title: 'Raw Material Stock',
    desc: 'Current balance of every raw material (recipe consumption draws from here).',
    run: () => ({
      columns: ['Material', 'Unit', 'Balance', 'Minimum', 'Status'],
      rows: db.prepare(
        `SELECT name, unit, stock, min_stock,
                CASE WHEN stock < min_stock THEN 'LOW' ELSE 'OK' END st
         FROM packing_materials WHERE category = 'Raw Material' ORDER BY name`
      ).all().map((r) => [r.name, r.unit, r.stock, r.min_stock, r.st]),
    }),
  },
  'raw-material-ledger': {
    title: 'Raw Material Ledger',
    desc: 'Every raw material receipt and consumption (recipe + manual).',
    run: () => ({
      columns: ['Date', 'Material', 'Type', 'Qty', 'Reference', 'Remark', 'By'],
      rows: db.prepare(
        `SELECT t.txn_date d, m.name mat, t.txn_type ty, t.qty q,
                COALESCE(t.reference,'') refr, COALESCE(t.remark,'') rem, COALESCE(u.name,'') byname
         FROM packing_txns t
         JOIN packing_materials m ON m.id = t.material_id
         LEFT JOIN users u ON u.id = t.created_by
         WHERE m.category = 'Raw Material'
         ORDER BY t.txn_date ASC, t.id ASC`
      ).all().map((r) => [r.d, r.mat, r.ty, r.q, r.refr, r.rem, r.byname]),
    }),
  },
  'packing-ledger': {
    title: 'Packing Material Ledger',
    desc: 'Every receipt and consumption entry.',
    run: () => ({
      columns: ['Date', 'Material', 'Type', 'Qty', 'Reference', 'Remark', 'By'],
      rows: db.prepare(
        `SELECT t.txn_date d, m.name, t.txn_type, t.qty, COALESCE(t.reference,'—') ref,
                COALESCE(t.remark,'—') rem, COALESCE(u.name,'—') who
         FROM packing_txns t JOIN packing_materials m ON m.id = t.material_id
         LEFT JOIN users u ON u.id = t.created_by
         ORDER BY t.txn_date ASC, t.id ASC`
      ).all().map((r) => [r.d, r.name, r.txn_type, r.qty, r.ref, r.rem, r.who]),
    }),
  },
};

const ROLE_REPORTS = {
  super_admin: Object.keys(REPORTS),
  admin: Object.keys(REPORTS),
  store_manager: ['inventory-valuation', 'batch-stock', 'low-stock', 'adjustment-register', 'approval-audit', 'dispatch-register', 'packing-stock', 'raw-material-stock', 'raw-material-ledger', 'packing-ledger'],
  store_keeper: ['inventory-valuation', 'batch-stock', 'low-stock', 'adjustment-register', 'packing-stock', 'raw-material-stock', 'raw-material-ledger', 'packing-ledger'],
  production_manager: ['production-output', 'inventory-valuation', 'batch-stock', 'packing-stock', 'raw-material-stock', 'raw-material-ledger', 'packing-ledger'],
  production_supervisor: ['production-output', 'packing-stock', 'raw-material-stock', 'raw-material-ledger', 'packing-ledger'],
  dispatch_manager: ['dispatch-register', 'inventory-valuation', 'batch-stock', 'production-output'],
  management_director: Object.keys(REPORTS),
};

router.use(requirePerm('reports.view'));

router.get('/', (req, res) => {
  const ids = ROLE_REPORTS[req.user.role] || [];
  res.json({ reports: ids.map((id) => ({ id, title: REPORTS[id].title, desc: REPORTS[id].desc })) });
});

/** Export the report table as a real Excel file — same role scope as viewing it. */
router.get('/:id.xlsx', (req, res) => {
  const id = req.params.id;
  const allowed = ROLE_REPORTS[req.user.role] || [];
  if (!REPORTS[id]) throw bad('Unknown report.', 404);
  if (!allowed.includes(id)) throw bad(`Report "${id}" is not available for your role.`, 403);
  const { columns, rows } = REPORTS[id].run();
  const clean = rows.map((r) => r.map((c) => (typeof c === 'number' ? c : String(c ?? ''))));
  const buf = xlsxBuffer(columns, clean, REPORTS[id].title.slice(0, 28));
  audit(db, req.user, 'EXPORT', 'report', id, `Report "${REPORTS[id].title}" exported to Excel`);
  res.setHeader('content-type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
  res.setHeader('content-disposition', `attachment; filename="flavorflow-${id}-${new Date().toISOString().slice(0, 10)}.xlsx"`);
  res.end(buf);
});

router.get('/:id', (req, res) => {
  const id = req.params.id;
  const allowed = ROLE_REPORTS[req.user.role] || [];
  if (!REPORTS[id]) throw bad('Unknown report.', 404);
  if (!allowed.includes(id)) throw bad(`Report "${id}" is not available for your role.`, 403);
  const data = REPORTS[id].run();
  res.json({ id, title: REPORTS[id].title, ...data });
});

module.exports = router;
