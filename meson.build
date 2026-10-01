project('the-giver', 'c',
  version: '0.1.0',
  license: 'MIT',
  meson_version: '>= 1.0',
  default_options: ['c_std=gnu11', 'warning_level=2', 'buildtype=debugoptimized'],
)

# The Linux frontend. The macOS app is built by macos/bundle.sh instead.
gtk = dependency('gtk4', version: '>= 4.12')
subdir('linux')
