'use strict';

const DEFAULT_DRUM_SHELF_LIFE_MONTHS = 24;

/**
 * Keep drum-fill products linked to the shared Product Master. Legacy drum-only
 * rows are reused by name when possible so existing fill history keeps its ID.
 */
function syncDrumProductCatalog(db) {
  const columns = db.prepare('PRAGMA table_info(drum_products)').all().map((column) => column.name);
  if (!columns.includes('master_product_id')) return 0;

  const now = new Date().toISOString();
  const masters = db.prepare(`
    SELECT id, name, active, shelf_life_months
      FROM products
     ORDER BY id
  `).all();
  const findLinked = db.prepare('SELECT id FROM drum_products WHERE master_product_id = ?');
  const findLegacyByName = db.prepare(`
    SELECT id FROM drum_products
     WHERE master_product_id IS NULL AND name = ? COLLATE NOCASE
     ORDER BY id LIMIT 1
  `);
  const findNameConflict = db.prepare(`
    SELECT id, master_product_id FROM drum_products
     WHERE name = ? COLLATE NOCASE
     ORDER BY id LIMIT 1
  `);
  const linkLegacy = db.prepare(`
    UPDATE drum_products
       SET master_product_id = ?, shelf_life_months = ?, active = ?, updated_at = ?
     WHERE id = ?
  `);
  const updateLinked = db.prepare(`
    UPDATE drum_products
       SET shelf_life_months = ?, active = ?, updated_at = ?
     WHERE id = ? AND (shelf_life_months <> ? OR active <> ?)
  `);
  const insertMapping = db.prepare(`
    INSERT INTO drum_products
      (master_product_id, code, name, shelf_life_months, active, created_at, updated_at)
    VALUES (?, NULL, ?, ?, ?, ?, ?)
  `);

  let linkedCount = 0;
  for (const product of masters) {
    const months = Number(product.shelf_life_months);
    const shelfLife = Number.isInteger(months) && months >= 1 && months <= 240
      ? months
      : DEFAULT_DRUM_SHELF_LIFE_MONTHS;
    const active = Number(product.active == null ? 1 : product.active) === 0 ? 0 : 1;
    let mapping = findLinked.get(product.id);

    if (!mapping) {
      mapping = findLegacyByName.get(product.name);
      if (mapping) {
        linkLegacy.run(product.id, shelfLife, active, now, mapping.id);
        linkedCount++;
        continue;
      }

      const conflict = findNameConflict.get(product.name);
      if (conflict) {
        // A same-named mapping linked to another master product should never
        // happen in normal use; leave it untouched rather than duplicate data.
        continue;
      }

      insertMapping.run(product.id, product.name, shelfLife, active, now, now);
      linkedCount++;
      continue;
    }

    updateLinked.run(shelfLife, active, now, mapping.id, shelfLife, active);
    linkedCount++;
  }

  return linkedCount;
}

module.exports = { syncDrumProductCatalog, DEFAULT_DRUM_SHELF_LIFE_MONTHS };
