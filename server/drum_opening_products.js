'use strict';

const { tx } = require('./sqlite');

/** Ensure aggregate drum products are available for individual fill entry too. */
function syncDrumProductsFromOpeningBalances(db) {
  const columns = db.prepare('PRAGMA table_info(drum_products)').all().map((column) => column.name);
  const hasMasterProductLink = columns.includes('master_product_id');
  const createdAt = new Date().toISOString();
  const existing = db.prepare('SELECT id FROM drum_products WHERE name = ? COLLATE NOCASE');
  const insert = db.prepare(`
    INSERT INTO drum_products (code, name, shelf_life_months, active, created_at, updated_at)
    VALUES (NULL, ?, 24, 1, ?, ?)
  `);

  return tx(db, () => {
    if (hasMasterProductLink) {
      // Earlier releases copied every Product Master item into Drum Stock.
      // Keep and unlink entries that have actual drum-stock history; remove
      // unused bottle-line-only mappings so they do not enter the fill selector.
      db.prepare(`
        UPDATE drum_products
           SET master_product_id = NULL, active = 1, updated_at = ?
         WHERE master_product_id IS NOT NULL
           AND (
             EXISTS (
               SELECT 1 FROM drum_opening_balances ob
                WHERE LOWER(TRIM(ob.product_name)) = LOWER(TRIM(drum_products.name))
             )
             OR EXISTS (
               SELECT 1 FROM drum_batches b WHERE b.product_id = drum_products.id
             )
             OR EXISTS (
               SELECT 1 FROM drum_stock_adjustments sa
                WHERE LOWER(TRIM(sa.product_name)) = LOWER(TRIM(drum_products.name))
             )
           )
      `).run(createdAt);
      db.prepare(`
        DELETE FROM drum_products
         WHERE master_product_id IS NOT NULL
           AND NOT EXISTS (
             SELECT 1 FROM drum_opening_balances ob
              WHERE LOWER(TRIM(ob.product_name)) = LOWER(TRIM(drum_products.name))
           )
           AND NOT EXISTS (
             SELECT 1 FROM drum_batches b WHERE b.product_id = drum_products.id
           )
           AND NOT EXISTS (
             SELECT 1 FROM drum_stock_adjustments sa
              WHERE LOWER(TRIM(sa.product_name)) = LOWER(TRIM(drum_products.name))
           )
      `).run();
    }

    let added = 0;
    for (const row of db.prepare(`
      SELECT DISTINCT TRIM(product_name) AS name
        FROM drum_opening_balances
       WHERE TRIM(COALESCE(product_name, '')) <> ''
       ORDER BY name COLLATE NOCASE
    `).all()) {
      if (existing.get(row.name)) continue;
      added += Number(insert.run(row.name, createdAt, createdAt).changes || 0);
    }

    return added;
  });
}

module.exports = { syncDrumProductsFromOpeningBalances };
