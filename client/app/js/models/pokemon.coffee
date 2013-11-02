class @Pokemon extends Backbone.Model
  defaults: =>
    name: 'Bulbasaur'
    moves: []
    pixels: 48
    ivs:
      hp: 31
      attack: 31
      defense: 31
      specialAttack: 31
      specialDefense: 31
      speed: 31
    evs:
      hp: 0
      attack: 0
      defense: 0
      specialAttack: 0
      specialDefense: 0
      speed: 0

  initialize: (attributes={}) ->
    @set('forme', 'default')  unless attributes.forme
    @normalizeStats(@get('ivs'), 31)
    @normalizeStats(@get('evs'), 0)

    # Skip teambuilder-specific properties.
    return  if @get('teambuilder') != true

    # Set to default ability when the species changes
    @on 'change:name', =>
      @set('ability', @getAbilities()[0], silent: true)

    @on 'change:ivs', (model, ivs)=>
      type = HiddenPower.BW.type(ivs).toLowerCase()
      @set("hiddenPowerType", type, silent: true)

    @on 'change:hiddenPowerType', (model, type) =>
      hpIVs = HiddenPower.BW.ivs[type.toLowerCase()]
      ivs = @get('ivs')
      for stat, iv of ivs
        ivs[stat] = hpIVs[stat] || 31
      @set('ivs', ivs, silent: true)

    @set('ability', @getAbilities()[0])  unless attributes.ability
    @set('level', 100)  unless attributes.level
    @set('happiness', 0)  unless attributes.happiness
    hiddenPowerType = HiddenPower.BW.type(@get('ivs')).toLowerCase()
    @set('hiddenPowerType', hiddenPowerType, silent: true)

  normalizeStats: (hash, defaultValue) ->
    stats = [ "hp", "attack", "defense", "specialAttack",
              "specialDefense", "speed"]
    for stat in stats
      hash[stat] ?= defaultValue

  getGeneration: (generation) ->
    gen = generation || @collection?.generation || DEFAULT_GENERATION
    gen = gen.toUpperCase()
    window.Generations[gen]

  getSpecies: ->
    @getGeneration().SpeciesData[@get('name')]

  getItem: ->
    @getGeneration().ItemData[@get('item')]

  getForme: (forme, generation) ->
    forme ||= @get('forme')
    @getGeneration(generation).FormeData[@get('name')]?[forme]

  getFormes: ->
    (forme  for forme of @getGeneration().FormeData[@get('name')])

  getAbilities: ->
    forme = @getForme()
    abilities = _.clone(forme.abilities)
    abilities.push(forme.hiddenAbility)  if forme.hiddenAbility
    _.unique(abilities)

  getGenders: ->
    species = @getSpecies()
    genders = []
    switch species.genderRatio
      when -1
        genders.push("Genderless")
      when 0
        genders.push("M")
      when 8
        genders.push("F")
      else
        genders.push("M", "F")
    genders

  getMovepool: ->
    {SpeciesData, MoveData} = @getGeneration()
    generation = GENERATION_TO_INT[@collection?.generation || DEFAULT_GENERATION]
    learnset = learnableMoves(window.Generations, SpeciesData, @attributes, generation)

    # Map each move name to a move object
    return _(learnset).map (moveName) ->
      move = _(MoveData[moveName]).clone()
      move['name'] = moveName
      move

  getTotalEVs: (options = {}) ->
    total = 0
    for stat, value of @get("evs")
      total += value  if stat != options.exclude
    total

  setIv: (stat, value) ->
    ivs = _.clone(@get("ivs"))
    ivs[stat] = value
    @set("ivs", ivs)  # trigger change event

  setEv: (stat, value) ->
    evs = _.clone(@get("evs"))
    total = @getTotalEVs(exclude: stat)
    value = Math.max(Math.min(value, 510 - total), 0)
    value = value - (value % 4)
    evs[stat] = value
    @set("evs", evs)  # trigger change event
    value

  iv: (stat) ->
    @get("ivs")[stat] ? 31

  ev: (stat) ->
    @get("evs")[stat] ? 0

  natureBoost: (stat) ->
    nature = @get('nature')?.toLowerCase()
    if nature of natures
      natures[nature][stat] || 1
    else
      1

  stat: (key) ->
    forme = @getForme()
    base = forme["stats"][key]
    return 1  if base == 1  # For Shedinja. key doesn't have to be hp.
    level = @get('level') || 100
    iv = @iv(key)
    ev = Math.floor(@ev(key) / 4)
    total = if key == 'hp'
      Math.floor((2 * base + iv + ev) * (level / 100) + level + 10)
    else
      Math.floor(((2 * base + iv + ev) * (level / 100) + 5) * @natureBoost(key))

  getNatures: ->
    (nature[0].toUpperCase() + nature.substr(1)  for nature of natures)

  setPP: (moveIndex, newPP) ->
    array = _.clone(@get('pp'))
    array[moveIndex] = newPP
    @set('pp', array)

  getPercentHP: ->
    Math.floor(100 * @get('pixels') / 48)

  isFainted: ->
    @get('pixels') <= 0

  getStatus: ->
    status = @get('status')
    if status
      "#{status[0].toUpperCase()}#{status.substr(1)}"
    else
      "Healthy"

  canMegaEvolve: ->
    item = @getItem()
    return false  if item.type != 'megastone'
    [ species, forme ] = item.mega
    return false  if @get('name') != species || @get('forme') != 'default'
    return true

  toJSON: ->
    attributes = _.clone(@attributes)
    delete attributes.hiddenPowerType
    attributes

# A hash that keys a nature with the stats that it boosts.
# Neutral natures are ignored.
# TODO: .yml-ify these.
PLUS  = 1.1
MINUS = 0.9
natures =
  lonely:  {attack: PLUS, defense: MINUS}
  brave:   {attack: PLUS, speed: MINUS}
  adamant: {attack: PLUS, specialAttack: MINUS}
  naughty: {attack: PLUS, specialDefense: MINUS}
  bold:    {defense: PLUS, attack: MINUS}
  relaxed: {defense: PLUS, speed: MINUS}
  impish:  {defense: PLUS, specialAttack: MINUS}
  lax:     {defense: PLUS, specialDefense: MINUS}
  timid:   {speed: PLUS, attack: MINUS}
  hasty:   {speed: PLUS, defense: MINUS}
  jolly:   {speed: PLUS, specialAttack: MINUS}
  naive:   {speed: PLUS, specialDefense: MINUS}
  modest:  {specialAttack: PLUS, attack: MINUS}
  mild:    {specialAttack: PLUS, defense: MINUS}
  quiet:   {specialAttack: PLUS, speed: MINUS}
  rash:    {specialAttack: PLUS, specialDefense: MINUS}
  calm:    {specialDefense: PLUS, attack: MINUS}
  gentle:  {specialDefense: PLUS, defense: MINUS}
  sassy:   {specialDefense: PLUS, speed: MINUS}
  careful: {specialDefense: PLUS, specialAttack: MINUS}

