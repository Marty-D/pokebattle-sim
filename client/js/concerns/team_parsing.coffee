@BattleTower ?= {}
@BattleTower.parseTeam = (teamString) ->
  text = teamString.split('\n')
  team = []
  for line in text
    line = line.replace(/^\s+/, '').replace(/\s+$/, '')
    if line.length == 0 || line == '---'
      if pokemon then team.push(pokemon)
      pokemon = null
    else if !pokemon
      [ pokemonLine, item ] = line.split(' @ ')
      possibleGender = pokemonLine[-4...]
      if possibleGender == ' (M)'
        gender = 'M'
        pokemonLine = pokemonLine[...-4]
      else if possibleGender == ' (F)'
        gender = 'F'
        pokemonLine = pokemonLine[...-4]
      else
        gender = null
      pokemon = {}
      # Ignore nicknames for now
      if pokemonLine.match(/(.*?)\s*\(.*\)/)
        pokemonLine = RegExp.$1
      pokemon.name = pokemonLine
      pokemon.gender = gender  if gender
      pokemon.item   = item    if item
    else if startsWith(line, "Trait: ")
      pokemon.ability = without(line, "Trait: ")
    else if line == 'Shiny: Yes'
      pokemon.shiny = true
    else if startsWith(line, "Level: ")
      pokemon.level = Number(without(line, "Level: ")) || 100
    else if startsWith(line, 'Happiness: ')
      pokemon.happiness = Number(without(line, "Happiness: ")) || 0
    else if startsWith(line, 'Ability: ')
      pokemon.ability = without(line, "Ability: ")
    else if startsWith(line, 'EVs: ')
      evs = without(line, 'EVs: ').split(/\//g)
      pokemon.evs = {}
      for ev in evs
        ev = ev.replace(/^\s+/, '').replace(/\s+$/, '')
        [ numberString, rawStat ] = ev.split(/\s+/)
        pokemon.evs[statsHash[rawStat]] = Number(numberString) || 0
    else if startsWith(line, 'IVs')
      ivs = without(line, 'IVs: ').split(/\//g)
      pokemon.ivs = {}
      for iv in ivs
        iv = iv.replace(/^\s+/, '').replace(/\s+$/, '')
        [ numberString, rawStat ] = iv.split(/\s+/)
        pokemon.ivs[statsHash[rawStat]] = Number(numberString) || 0
    else if line.match(/^([A-Za-z]+) (N|n)ature/)
      pokemon.nature = RegExp.$1
    else if startsWith(line, '-') || startsWith(line, '~')
      moveName = line.substr(1).replace(/^\s+/, '')
      if startsWith(moveName, 'Hidden Power [')
        if !pokemon.ivs
          moveName.match(/Hidden Power \[\s*(.*)\s*\]/)
          hiddenPowerType = RegExp.$1.toLowerCase()
          pokemon.ivs = hiddenPowerIVs[hiddenPowerType] || {}
        moveName = 'Hidden Power'
      pokemon.moves ?= []
      pokemon.moves.push(moveName)
  return team

startsWith = (string, suffix) ->
  string[...suffix.length] == suffix

without = (string, suffix) ->
  string[suffix.length...]

statsHash =
  'HP'   : 'hp'
  'Atk'  : 'attack'
  'Def'  : 'defense'
  'SAtk' : 'specialAttack'
  'SDef' : 'specialDefense'
  'Spe'  : 'speed'

hiddenPowerIVs =
  bug:
    attack: 30
    defense: 30
    specialDefense: 30
  dark: {}
  dragon:
    attack: 30
  electric:
    specialAttack: 30
  fighting:
    defense: 30
    specialAttack: 30
    specialDefense: 30
    speed: 30
  fire:
    attack: 30
    specialAttack: 30
    speed: 30
  flying:
    hp: 30
    attack: 30
    defense: 30
    specialAttack: 30
    specialDefense: 30
  ghost:
    defense: 30
    specialDefense: 30
  grass:
    attack: 30
    specialAttack: 30
  ground:
    specialAttack: 30
    specialDefense: 30
  ice:
    attack: 30
    defense: 30
  poison:
    defense: 30
    specialAttack: 30
    specialDefense: 30
  psychic:
    attack: 30
    speed: 30
  rock:
    defense: 30
    specialDefense: 30
    speed: 30
  steel:
    specialDefense: 30
  water:
    attack: 30
    defense: 30
    specialAttack: 30
