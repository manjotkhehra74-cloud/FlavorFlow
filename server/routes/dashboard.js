/**
 * routes/dashboard.js — server-computed, per-role dashboards.
 * Every profile receives a completely different set of KPIs, charts,
 * tables, alerts and quick actions. Quantities only — no pricing.
 */
const express = require('express');
const db = require('../db');
const { requirePerm } = require('../middleware');

const router = express.Router();
router.use(requirePerm('dashboard.view'));

/* ---- reusable aggregates ---- */

const stockSummary = () =>
  db.prepare(`SELECT COALESCE(SUM(i.qty_cb),0) cb, COALESCE(SUM(i.qty_trays),0) trays,
              COALESCE(SUM(i.qty_cb * p.bottles_per_cb + i.qty_trays * p.bottles_per_tray),0) bottles
              FROM inventory i JOIN products p ON p.id = i.product_id WHERE p.active = 1`).get();

const lowStockRows = () =>
  db.prepare(`SELECT p.id, p.name, i.qty_cb, p.min_stock_cb
              FROM inventory i JOIN products p ON p.id = i.product_id
              WHERE p.active = 1 AND i.qty_cb < p.min_stock_cb ORDER BY i.qty_cb ASC`).all();

const packingLowRows = () =>
  db.prepare(`SELECT name, stock, min_stock, unit FROM packing_materials WHERE stock < min_stock ORDER BY stock ASC`).all();

const pendingApprovals = () =>
  db.prepare(`SELECT id, code, qty_cb, adj_type, reason FROM adjustments WHERE status='PENDING' ORDER BY requested_at`).all();

const monthKpis = () => ({
  dispatchCount: db.prepare(`SELECT COUNT(*) v FROM dispatches WHERE strftime('%Y-%m', created_at) = strftime('%Y-%m','now')`).get().v,
  dispatchWeight: db.prepare(`SELECT COALESCE(SUM(gross_weight),0) v FROM dispatches WHERE strftime('%Y-%m', created_at) = strftime('%Y-%m','now')`).get().v,
  dispatchBottles: db.prepare(`SELECT COALESCE(SUM(total_bottles),0) v FROM dispatches WHERE strftime('%Y-%m', created_at) = strftime('%Y-%m','now')`).get().v,
  producedCb: db.prepare(`SELECT COALESCE(SUM(produced_cb),0) v FROM batches WHERE status='COMPLETED' AND strftime('%Y-%m', completed_at) = strftime('%Y-%m','now')`).get().v,
});

function last14(table, dateCol, aggr, where = '') {
  const days = [];
  for (let i = 13; i >= 0; i--) days.push(new Date(Date.now() - i * 86400000).toISOString().slice(0, 10));
  const rows = db.prepare(
    `SELECT date(${dateCol}) d, ${aggr} v FROM ${table} ${where}
     AND date(${dateCol}) >= date('now', '-13 days') GROUP BY date(${dateCol})`
  ).all();
  const map = Object.fromEntries(rows.map((r) => [r.d, r.v]));
  return { labels: days.map((d) => d.slice(8)), values: days.map((d) => +(map[d] || 0).toFixed(2)) };
}

const productionTrend = () =>
  last14('batches', 'completed_at', 'COALESCE(SUM(produced_cb),0)', `WHERE status='COMPLETED'`);

const dispatchTrend = () =>
  last14('dispatches', 'created_at', 'COALESCE(SUM(gross_weight),0)', 'WHERE 1=1');

const dispatchCountTrend = () =>
  last14('dispatches', 'created_at', 'COUNT(*)', 'WHERE 1=1');

const stockPie = () => {
  const rows = db.prepare(
    `SELECT p.name, i.qty_cb v FROM inventory i JOIN products p ON p.id = i.product_id
     WHERE p.active = 1 AND i.qty_cb > 0 ORDER BY v DESC`
  ).all();
  const top = rows.slice(0, 6);
  const rest = rows.slice(6).reduce((a, r) => a + r.v, 0);
  const labels = top.map((r) => r.name);
  const values = top.map((r) => r.v);
  if (rest > 0) { labels.push('Others'); values.push(rest); }
  return { labels, values };
};

const recentDispatches = (n = 5) =>
  db.prepare(`SELECT code, truck_number, destination, total_cartons, total_trays, gross_weight, date(created_at) d
              FROM dispatches ORDER BY created_at DESC LIMIT ?`).all(n);

const recentBatches = (n = 6) =>
  db.prepare(`SELECT b.code, p.name product, b.planned_cb, b.produced_cb, b.produced_trays, b.status, date(COALESCE(b.completed_at, b.created_at)) d
              FROM batches b JOIN products p ON p.id = b.product_id ORDER BY b.created_at DESC LIMIT ?`).all(n);

const lowStockAlerts = () => lowStockRows().map((r) => ({
  severity: r.qty_cb <= r.min_stock_cb / 2 ? 'high' : 'medium',
  text: `${r.name}: ${r.qty_cb} CB in stock (min ${r.min_stock_cb} CB)`,
  route: '/inventory?filter=low',
}));

const packingAlerts = () => packingLowRows().map((m) => ({
  severity: m.stock <= 0 ? 'high' : 'medium',
  text: `Packing material low: ${m.name} — ${m.stock} ${m.unit} (min ${m.min_stock})`,
  route: '/packing?filter=low',
}));

const approvalAlerts = () => pendingApprovals().map((a) => ({
  severity: 'high', text: `${a.code}: ${a.adj_type} ${a.qty_cb} CB — ${a.reason}`,
  route: `/approvals?focus=${a.id}`,
}));

const kpi = (label, value, opts = {}) => ({ label, value, money: false, ...opts });

const dispatchTable = (n, route = '/dispatch') => ({
  columns: ['Code', 'Truck', 'Destination', 'Cartons', 'Trays', 'Gross kg', 'Date'],
  rows: recentDispatches(n).map((d) => [d.code, d.truck_number, d.destination || '—', d.total_cartons, d.total_trays, d.gross_weight, d.d]),
  route,
});

const batchTable = (n) => ({
  columns: ['Batch', 'Product', 'Planned CB', 'Produced CB', 'Trays', 'Status'],
  rows: recentBatches(n).map((b) => [b.code, b.product, b.planned_cb, b.produced_cb, b.produced_trays, b.status]),
  route: '/production',
});

/* ---- per-role dashboard builders ---- */

function build(role, user) {
  const m = monthKpis();
  const s = stockSummary();
  const widgets = [];
  const W = (type, title, opts = {}) => widgets.push({ type, title, ...opts });

  if (role === 'super_admin') {
    const usersByRole = db.prepare(`SELECT role, COUNT(*) c FROM users GROUP BY role ORDER BY c DESC`).all();
    W('kpi', 'Key Performance Indicators', {
      items: [
        kpi('Active Users', db.prepare('SELECT COUNT(*) v FROM users WHERE active=1').get().v, { icon: 'group', tint: '#7C3AED' }),
        kpi('Products (FG)', db.prepare('SELECT COUNT(*) v FROM products WHERE active=1').get().v, { icon: 'inventory_2', tint: '#2563EB' }),
        kpi('Stock on Hand (CB)', s.cb, { icon: 'warehouse', tint: '#059669' }),
        kpi('Trips (Month)', m.dispatchCount, { icon: 'local_shipping', tint: '#EA580C' }),
        kpi('Pending Approvals', pendingApprovals().length, { icon: 'fact_check', tint: '#D97706' }),
      ],
    });
    W('alerts', 'System Alerts', { items: [...approvalAlerts(), ...lowStockAlerts(), ...packingAlerts()] });
    W('line', 'Production Output — last 14 days (CB)', productionTrend());
    W('bar', 'Dispatch Volume — last 14 days (trips)', dispatchCountTrend());
    W('table', 'Users by Role', { columns: ['Role', 'Users'], rows: usersByRole.map((r) => [r.role.replace(/_/g, ' '), r.c]), route: '/users' });
    W('actions', 'Quick Actions', {
      items: [
        { label: 'Manage Users', route: '/users', icon: 'group' },
        { label: 'Audit Log', route: '/audit', icon: 'history' },
        { label: 'Reports', route: '/reports', icon: 'bar_chart' },
      ],
    });
  }

  if (role === 'admin') {
    W('kpi', 'Business Overview', {
      items: [
        kpi('Stock on Hand (CB)', s.cb, { icon: 'warehouse', tint: '#0891B2' }),
        kpi('Total Bottles', s.bottles, { icon: 'liquor', tint: '#2563EB' }),
        kpi('Trips (Month)', m.dispatchCount, { icon: 'local_shipping', tint: '#EA580C' }),
        kpi('Produced (Month, CB)', m.producedCb, { icon: 'manufacturing', tint: '#0D9488' }),
        kpi('Pending Approvals', pendingApprovals().length, { icon: 'fact_check', tint: '#D97706' }),
      ],
    });
    W('alerts', 'Action Required', { items: [...approvalAlerts(), ...lowStockAlerts(), ...packingAlerts()] });
    W('line', 'Production Output — last 14 days (CB)', productionTrend());
    W('bar', 'Dispatch Weight — last 14 days (kg)', dispatchTrend());
    W('pie', 'Inventory by Product (CB)', stockPie());
    W('table', 'Recent Dispatches', dispatchTable());
    W('actions', 'Quick Actions', {
      items: [
        { label: 'Approve Adjustments', route: '/approvals', icon: 'fact_check' },
        { label: 'New Dispatch', route: '/dispatch', icon: 'local_shipping' },
        { label: 'User Management', route: '/users', icon: 'group' },
        { label: 'Reports', route: '/reports', icon: 'bar_chart' },
      ],
    });
  }

  if (role === 'production_manager') {
    W('kpi', 'Production Overview', {
      items: [
        kpi('Batches In Progress', db.prepare(`SELECT COUNT(*) v FROM batches WHERE status='IN_PROGRESS'`).get().v, { icon: 'manufacturing', tint: '#0891B2' }),
        kpi('Planned Batches', db.prepare(`SELECT COUNT(*) v FROM batches WHERE status='PLANNED'`).get().v, { icon: 'event_note', tint: '#C026D3' }),
        kpi('Produced (Month, CB)', m.producedCb, { icon: 'check_circle', tint: '#059669' }),
        kpi('Stock on Hand (CB)', s.cb, { icon: 'warehouse', tint: '#D97706' }),
      ],
    });
    W('line', 'Output Trend — last 14 days (CB)', productionTrend());
    W('table', 'Recent Batches', batchTable(8));
    W('alerts', 'Stock Alerts', { items: [...lowStockAlerts(), ...packingAlerts()] });
    W('actions', 'Quick Actions', {
      items: [
        { label: 'New Batch', route: '/production', icon: 'add_circle' },
        { label: 'Packing Material', route: '/packing', icon: 'widgets' },
        { label: 'Reports', route: '/reports', icon: 'bar_chart' },
      ],
    });
  }

  if (role === 'production_supervisor') {
    const mine = db.prepare(`SELECT COUNT(*) v FROM batches WHERE status='IN_PROGRESS'`).get().v;
    const today = db.prepare(`SELECT COALESCE(SUM(produced_cb),0) v FROM batches WHERE status='COMPLETED' AND date(completed_at)=date('now')`).get().v;
    W('kpi', 'Shop Floor Today', {
      items: [
        kpi('Active Batches', mine, { icon: 'manufacturing', tint: '#0891B2' }),
        kpi('Produced Today (CB)', today, { icon: 'check_circle', tint: '#059669' }),
        kpi('Queued Batches', db.prepare(`SELECT COUNT(*) v FROM batches WHERE status='PLANNED'`).get().v, { icon: 'pending', tint: '#D97706' }),
        kpi('Stock on Hand (CB)', s.cb, { icon: 'warehouse', tint: '#2563EB' }),
      ],
    });
    W('table', 'Batches Needing Action', {
      columns: ['Batch', 'Product', 'Planned CB', 'Produced CB', 'Status'],
      rows: recentBatches(8).filter((b) => b.status !== 'COMPLETED').map((b) => [b.code, b.product, b.planned_cb, b.produced_cb, b.status]),
      route: '/production',
    });
    W('line', 'Team Output — last 14 days (CB)', productionTrend());
    W('alerts', 'Packing Material Alerts', { items: packingAlerts() });
    W('actions', 'Quick Actions', {
      items: [{ label: 'Open Production', route: '/production', icon: 'manufacturing' }],
    });
  }

  if (role === 'store_manager') {
    W('kpi', 'Store Overview', {
      items: [
        kpi('Stock on Hand (CB)', s.cb, { icon: 'warehouse', tint: '#0891B2' }),
        kpi('Trays on Hand', s.trays, { icon: 'dinner_dining', tint: '#0D9488' }),
        kpi('Low Stock Items', lowStockRows().length, { icon: 'warning', tint: '#DC2626' }),
        kpi('Packing Items Low', packingLowRows().length, { icon: 'widgets', tint: '#EA580C' }),
        kpi('Pending Approvals', pendingApprovals().length, { icon: 'fact_check', tint: '#D97706' }),
      ],
    });
    W('alerts', 'Approvals & Stock Alerts', { items: [...approvalAlerts(), ...lowStockAlerts(), ...packingAlerts()] });
    W('pie', 'Inventory by Product (CB)', stockPie());
    W('table', 'Low Stock Products', {
      columns: ['Product', 'In Stock (CB)', 'Minimum (CB)'],
      rows: lowStockRows().map((r) => [r.name, r.qty_cb, r.min_stock_cb]),
      route: '/inventory?filter=low',
    });
    W('actions', 'Quick Actions', {
      items: [
        { label: 'Approve Adjustments', route: '/approvals', icon: 'fact_check' },
        { label: 'Receive Stock', route: '/inventory', icon: 'add_box' },
        { label: 'Packing Material', route: '/packing', icon: 'widgets' },
        { label: 'Reports', route: '/reports', icon: 'bar_chart' },
      ],
    });
  }

  if (role === 'store_keeper') {
    const myPending = db.prepare(`SELECT COUNT(*) v FROM adjustments WHERE status='PENDING' AND requested_by=?`).get(user.id).v;
    W('kpi', 'My Store Desk', {
      items: [
        kpi('Stock on Hand (CB)', s.cb, { icon: 'warehouse', tint: '#0891B2' }),
        kpi('Low Stock Items', lowStockRows().length, { icon: 'warning', tint: '#DC2626' }),
        kpi('My Pending Requests', myPending, { icon: 'pending_actions', tint: '#D97706' }),
        kpi('Packing Items', db.prepare('SELECT COUNT(*) v FROM packing_materials').get().v, { icon: 'widgets', tint: '#65A30D' }),
      ],
    });
    W('alerts', 'Stock Alerts', { items: [...lowStockAlerts(), ...packingAlerts()] });
    W('table', 'Low Stock Products', {
      columns: ['Product', 'In Stock (CB)', 'Minimum (CB)'],
      rows: lowStockRows().map((r) => [r.name, r.qty_cb, r.min_stock_cb]),
      route: '/inventory?filter=low',
    });
    W('actions', 'Quick Actions', {
      items: [
        { label: 'Request Adjustment', route: '/adjustments', icon: 'tune' },
        { label: 'View Inventory', route: '/inventory', icon: 'warehouse' },
        { label: 'Packing Material', route: '/packing', icon: 'widgets' },
      ],
    });
  }

  if (role === 'dispatch_manager') {
    W('kpi', 'Dispatch Overview', {
      items: [
        kpi('Trips (Month)', m.dispatchCount, { icon: 'local_shipping', tint: '#EA580C' }),
        kpi('Weight Dispatched (kg)', m.dispatchWeight, { icon: 'scale', tint: '#0891B2' }),
        kpi('Bottles Dispatched (Month)', m.dispatchBottles, { icon: 'liquor', tint: '#2563EB' }),
        kpi('Stock on Hand (CB)', s.cb, { icon: 'warehouse', tint: '#D97706' }),
      ],
    });
    W('bar', 'Dispatch Weight — last 14 days (kg)', dispatchTrend());
    W('table', 'Recent Dispatches', dispatchTable(8));
    W('alerts', 'Stock Alerts', { items: [...lowStockAlerts(), ...packingAlerts()] });
    W('actions', 'Quick Actions', {
      items: [
        { label: 'New Dispatch', route: '/dispatch', icon: 'add_circle' },
        { label: 'Truck Calculator', route: '/dispatch?tab=calculator', icon: 'calculate' },
        { label: 'Reports', route: '/reports', icon: 'bar_chart' },
      ],
    });
  }

  if (role === 'management_director') {
    W('kpi', 'Executive Overview — Read Only', {
      items: [
        kpi('Stock on Hand (CB)', s.cb, { icon: 'warehouse', tint: '#059669' }),
        kpi('Total Bottles', s.bottles, { icon: 'liquor', tint: '#2563EB' }),
        kpi('Trips (Month)', m.dispatchCount, { icon: 'local_shipping', tint: '#EA580C' }),
        kpi('Weight Dispatched (kg)', m.dispatchWeight, { icon: 'scale', tint: '#0891B2' }),
        kpi('Produced (Month, CB)', m.producedCb, { icon: 'manufacturing', tint: '#0D9488' }),
        kpi('Pending Approvals', pendingApprovals().length, { icon: 'fact_check', tint: '#D97706' }),
      ],
    });
    W('line', 'Production Output — last 14 days (CB)', productionTrend());
    W('bar', 'Dispatch Weight — last 14 days (kg)', dispatchTrend());
    W('pie', 'Inventory by Product (CB)', stockPie());
    W('alerts', 'Attention Areas', { items: [...approvalAlerts(), ...lowStockAlerts(), ...packingAlerts()] });
    W('table', 'Recent Dispatches', dispatchTable(6));
    W('actions', 'Quick Actions', {
      items: [
        { label: 'All Reports', route: '/reports', icon: 'bar_chart' },
        { label: 'Audit Log', route: '/audit', icon: 'history' },
      ],
    });
  }

  return widgets;
}

router.get('/', (req, res) => {
  res.json({
    role: req.user.role,
    name: req.user.name,
    greeting: greeting(),
    widgets: build(req.user.role, req.user),
  });
});

function greeting() {
  const istHour = (new Date().getUTCHours() + 5.5) % 24;
  if (istHour < 12) return 'Good morning';
  if (istHour < 17) return 'Good afternoon';
  return 'Good evening';
}

module.exports = router;
