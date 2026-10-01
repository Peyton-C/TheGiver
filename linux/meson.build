executable('the-giver', 'main.c',
  dependencies: gtk,
  install: true,
)

install_data('io.github.peyton_c.TheGiver.desktop',
  install_dir: get_option('datadir') / 'applications',
)

import('gnome').post_install(
  gtk_update_icon_cache: true,
  update_desktop_database: true,
)
# 512x512 is the largest size the hicolor theme lists. An icon installed
# under any other directory name is never looked up.
install_data('../assets/the_giver_icon/the_giver_512.png',
  rename: 'io.github.peyton_c.TheGiver.png',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / '512x512' / 'apps',
)
