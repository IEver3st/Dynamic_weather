const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const test = require('node:test')

const root = path.resolve(__dirname, '..')
const read = (relativePath) => fs.readFileSync(path.join(root, relativePath), 'utf8')

const removedTerms = [
  new RegExp(['fl', 'ood'].join(''), 'i'),
  new RegExp(['sea', '.?', 'level'].join(''), 'i'),
  new RegExp(['water', '.?', 'level'].join(''), 'i'),
  new RegExp(['protected', '.?', 'water'].join(''), 'i'),
  new RegExp(['ignore', '.?', 'zone'].join(''), 'i'),
]

function listFiles(relativeDirectory) {
  const directory = path.join(root, relativeDirectory)
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const relativePath = path.join(relativeDirectory, entry.name)
    return entry.isDirectory() ? listFiles(relativePath) : [relativePath]
  })
}

test('runtime and editor sources contain no removed subsystem wiring', () => {
  const files = [
    'fxmanifest.lua',
    'init.lua',
    'README.md',
    'shared/config.lua',
    '.github/workflows/release.yml',
    ...listFiles('modules'),
    ...listFiles('web/src'),
  ]

  for (const relativePath of files) {
    const source = read(relativePath)
    for (const pattern of removedTerms) {
      assert.doesNotMatch(source, pattern, relativePath)
    }
  }
})

test('removed runtime assets and data are absent', () => {
  const removedPaths = [
    ['fl', 'ood.xml'].join(''),
    ['fl', 'ood_calm.xml'].join(''),
    ['water', '_levels'].join(''),
    path.join('docs', ['sea', '_level.md'].join('')),
    path.join('modules', 'client', ['sea', '_level.lua'].join('')),
    path.join('modules', 'server', ['sea', '_level.lua'].join('')),
    path.join('modules', 'server', ['fl', 'ood_event.lua'].join('')),
    path.join('modules', 'shared', ['fl', 'ood_', 'ign', 'ore_zones.lua'].join('')),
    path.join('modules', 'shared', ['protected', '_water.lua'].join('')),
    path.join('shared', 'data', ['fl', 'ood_settings.json'].join('')),
    path.join('shared', 'data', ['fl', 'ood_', 'ign', 'ore_zones.json'].join('')),
    path.join('shared', 'data', ['protected', '_water.json'].join('')),
    path.join('web', 'src', ['Fl', 'oodPanel.jsx'].join('')),
  ]

  for (const relativePath of removedPaths) {
    assert.equal(fs.existsSync(path.join(root, relativePath)), false, relativePath)
  }
})

test('weather editor saves and reloads zones only', () => {
  const editor = read('web/src/Editor.jsx')
  const nui = read('modules/client/nui.lua')

  assert.match(editor, /postNui\('dw_saveZones', \{ zones \}\)/)
  assert.match(editor, /postNui\('dw_requestZones'\)/)
  assert.match(nui, /RegisterNUICallback\('dw_saveZones'/)
  assert.match(nui, /cb\(\{ zones = defs, states = states \}\)/)
})

test('compiled NUI contains no removed feature protocol', () => {
  const bundle = listFiles('web/dist')
    .filter((relativePath) => /\.(?:html|css|js)$/.test(relativePath))
    .map(read)
    .join('\n')
  const removedProtocolTokens = [
    ['dynamic_weather_', 'fl', 'ood'].join(''),
    ['dw_save', 'Fl', 'ood'].join(''),
    ['fl', 'oodSettings'].join(''),
    ['fl', 'oodIgnore'].join(''),
    ['sea', 'Level'].join(''),
    ['protected', 'Water'].join(''),
  ]

  for (const token of removedProtocolTokens) {
    assert.equal(bundle.includes(token), false, token)
  }
})

test('remaining manifest and release package require weather data', () => {
  const manifest = read('fxmanifest.lua')
  const workflow = read('.github/workflows/release.yml')

  assert.match(manifest, /shared\/data\/zones\.json/)
  assert.match(manifest, /shared\/data\/sequences\.json/)
  assert.match(workflow, /shared\/data\/zones\.json/)
  assert.equal(fs.existsSync(path.join(root, 'shared/data/zones.json')), true)
  assert.equal(fs.existsSync(path.join(root, 'shared/data/sequences.json')), true)
})
