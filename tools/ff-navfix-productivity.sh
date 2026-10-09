#!/usr/bin/env bash
# Fix NAV_ITEMS to include all sections including productivity, stock, billing, etc.
set -u
cd /opt/flavorflow/server || exit 1
TS=$(date +%s)
cp -a rbac.js "/opt/flavorflow/backups/rbac.js.bak-navfix-$TS"
node <<'JS'
const fs=require('fs');
let src=fs.readFileSync('rbac.js','utf8');
let changed=false;

// Ensure NAV_ITEMS has all required entries
const requiredNav = [
  {path:'/dashboard', label:'Dashboard', icon:'dashboard', perm:'dashboard.view', group:'Overview'},
  {path:'/products', label:'Product Master', icon:'inventory_2', perm:'products.view', group:'Operations'},
  {path:'/inventory', label:'Inventory', icon:'warehouse', perm:'inventory.view', group:'Operations'},
  {path:'/stock', label:'Stock Ledger', icon:'history', perm:'stock.view', group:'Operations'},
  {path:'/packing', label:'Packing Material', icon:'widgets', perm:'packing.view', group:'Operations'},
  {path:'/raw', label:'Raw Material', icon:'science', perm:'raw.view', group:'Operations'},
  {path:'/loss', label:'Packing Loss %', icon:'percent', perm:'loss.view', group:'Operations'},
  {path:'/production', label:'Production', icon:'manufacturing', perm:'production.view', group:'Operations'},
  {path:'/dispatch', label:'Dispatch', icon:'local_shipping', perm:'dispatch.view', group:'Operations'},
  {path:'/billing', label:'Billing', icon:'receipt_long', perm:'billing.view', group:'Operations'},
  {path:'/adjustments', label:'Stock Adjustments', icon:'tune', perm:'adjustments.view', group:'Stock Control'},
  {path:'/approvals', label:'Approvals', icon:'fact_check', perm:'adjustments.approve', group:'Stock Control'},
  {path:'/reports', label:'Reports', icon:'bar_chart', perm:'reports.view', group:'Insights'},
  {path:'/productivity', label:'Productivity & Labour', icon:'analytics', perm:'productivity.view', group:'Insights'},
  {path:'/users', label:'User Management', icon:'group', perm:'users.view', group:'Administration'},
  {path:'/audit', label:'Audit Log', icon:'history', perm:'audit.view', group:'Administration'},
  {path:'/settings', label:'Settings', icon:'settings', perm:'settings.view', group:'Administration'},
  {path:'/notifications', label:'Notifications', icon:'notifications', perm:'notifications.view', group:'System'},
];

const navMatch = src.match(/const NAV_ITEMS\s*=\s*\[([\s\S]*?)\];/);
if (!navMatch) {
  console.log('NAV_ITEMS not found, creating new');
  const navStr = requiredNav.map(n=>`  { path: '${n.path}', label: '${n.label}', icon: '${n.icon}', perm: '${n.perm}', group: '${n.group}' },`).join('\n');
  // Find where to insert - before module.exports or at end
  if (src.includes('module.exports')) {
    src = src.replace(/module\.exports/, `const NAV_ITEMS = [\n${navStr}\n];\n\nmodule.exports`);
  } else {
    src += `\nconst NAV_ITEMS = [\n${navStr}\n];\n`;
  }
  changed=true;
} else {
  let navContent = navMatch[1];
  let existingPaths = [...navContent.matchAll(/path:\s*'([^']+)'/g)].map(m=>m[1]);
  console.log('Existing NAV paths:', existingPaths);
  let missing = requiredNav.filter(r=>!existingPaths.includes(r.path));
  console.log('Missing NAV paths:', missing.map(m=>m.path));
  if (missing.length>0) {
    // Add missing entries before closing ];
    const addStr = missing.map(n=>`  { path: '${n.path}', label: '${n.label}', icon: '${n.icon}', perm: '${n.perm}', group: '${n.group}' },`).join('\n');
    const newNavContent = navContent.trimEnd() + '\n' + addStr + '\n';
    src = src.replace(/const NAV_ITEMS\s*=\s*\[([\s\S]*?)\];/, `const NAV_ITEMS = [${newNavContent}];`);
    changed=true;
    console.log(`Added ${missing.length} NAV_ITEMS`);
  } else {
    console.log('All NAV_ITEMS present');
  }
}

if (changed) {
  fs.writeFileSync('rbac.js', src);
  console.log('rbac.js NAV_ITEMS updated');
} else {
  console.log('No NAV changes needed');
}
JS
echo "Restarting flavorflow"
sudo systemctl restart flavorflow
sleep 3
curl -s http://127.0.0.1:4000/api/health
echo ""
echo "Done"
