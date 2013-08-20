@MoveData = require('./data_moves.json')
{Weather} = require('../../server/weather')
{Move} = require('../../server/move')
{Status} = require('../../server/status')
{Attachment} = require('../../server/attachment')
{Protocol} = require('../../shared/protocol')
{_} = require 'underscore'
util = require '../../server/util'
hiddenPower = require '../../shared/hidden_power'

# Generate the initial versions of every single move.
# Many will be overwritten later.
@Moves = Moves = {}
@MoveList = MoveList = []
for name, attributes of @MoveData
  @Moves[name] = new Move(name, attributes)
  MoveList.push(@Moves[name])

# Extends a move in the move list using a callback.
#
# name -      The name of the move to extend.
# callback -  The function that will extend the move. 'this'
#             is the move object itself.
#
# Example:
#
#   extendMove 'Substitute', (attributes) ->
#     @initialize -> # blah
#     @afterMove -> # blah
#
extendMove = (name, callback) ->
  if name not of Moves
    throw new Error("Cannot extend Move '#{name}' because it does not exist.")

  move = Moves[name]
  callback.call(move, move.attributes)

extendWithPrimaryEffect = (name, Klass, options={}) ->
  extendMove name, ->
    @afterSuccessfulHit = (battle, user, target, damage) ->
      if target.has(Klass)
        # TODO: Placeholder
        @fail(battle)
        return

      target.attach(Klass, options)

extendWithPrimaryStatus = (name, status) ->
  extendMove name, ->
    @afterSuccessfulHit = (battle, user, target, damage) ->
      target.attach(status)

# Extends a move in the move list as an attack with a secondary effect.
#
# name - The name of the move to turn into a secondary effect attack.
# chance - The chance that the secondary effect will activate
# effect - The constructor of the status to inflict
#
# Example:
#
#   extendWithSecondaryEffect 'Iron Head', .3, Attachment.Flinch
#
extendWithSecondaryEffect = (name, chance, Klass, options={}) ->
  extendMove name, ->
    oldFunc = @afterSuccessfulHit
    @afterSuccessfulHit = (battle, user, target, damage) ->
      oldFunc.call(this, battle, user, target, damage)
      if battle.rng.next("secondary effect") >= chance
        return

      target.attach(Klass, options)

extendWithSecondaryStatus = (name, chance, status) ->
  extendMove name, ->
    oldFunc = @afterSuccessfulHit
    @afterSuccessfulHit = (battle, user, target, damage) ->
      oldFunc.call(this, battle, user, target, damage)
      if battle.rng.next("secondary status") >= chance
        return

      target.attach(status)

# The fang moves have an additional 10% chance to flinch.
extendWithFangEffect = (name, chance, status, options) ->
  extendMove name, ->
    @afterSuccessfulHit = (battle, user, target, damage) ->
      if battle.rng.next("fang status") < chance
        target.attach(status)

      if battle.rng.next("fang flinch") < chance
        target.attach(Attachment.Flinch)

extendWithDrain = (name, drainPercent=.5) ->
  extendMove name, ->
    oldFunc = @afterSuccessfulHit
    @afterSuccessfulHit = (battle, user, target, damage) ->
      amount = Math.floor(damage * drainPercent)
      user.drain(amount, target)
      # TODO: Message after drain
      battle.message "#{user.name} absorbed some HP!"
      oldFunc.call(this, battle, user, target, damage)

makeJumpKick = (name, recoilPercent=.5) ->
  extendMove name, ->
    @afterMiss = (battle, user, target, damage) ->
      amount = Math.floor(damage * recoilPercent)
      user.damage(amount)
      battle.message("#{user.name} kept going and crashed!")

makeWeightBased = (name) ->
  extendMove name, ->
    @basePower = (battle, user, target) ->
      weight = target.calculateWeight()
      if weight <= 100       then 20
      else if weight <= 250  then 40
      else if weight <= 500  then 60
      else if weight <= 1000 then 80
      else if weight <= 2000 then 100
      else                        120

makeWeightRatioBased = (name) ->
  extendMove name, ->
    @basePower = (battle, user, target) ->
      n = target.calculateWeight() / user.calculateWeight()
      if n < .2       then 120
      else if n < .25 then 100
      else if n < 1/3 then 80
      else if n < .5  then 60
      else                 40

makeLevelAsDamageMove = (name) ->
  extendMove name, ->
    @calculateDamage = (battle, user, target) ->
      user.level

makeReversalMove = (name) ->
  extendMove name, ->
    @basePower = (battle, user, target) ->
      n = Math.floor(64 * user.currentHP / user.stat('hp'))
      if n <= 1       then 200
      else if n <= 5  then 150
      else if n <= 12 then 100
      else if n <= 21 then 80
      else if n <= 42 then 40
      else if n <= 64 then 20

makeEruptionMove = (name) ->
  extendMove name, ->
    @basePower = (battle, user, target) ->
      power = Math.floor(150 * (user.currentHP / user.stat('hp')))
      Math.max(power, 1)

makeStatusCureAttackMove = (moveName, status) ->
  extendMove moveName, ->
    @basePower = (battle, user, target) ->
      if target.has(status) then 2 * @power else @power

    @afterSuccessfulHit = (battle, user, target) ->
      target.cureStatus(status)

makeOneHitKOMove = (name) ->
  extendMove name, ->
    @flags.push("ohko")

    @calculateDamage = (battle, user, target) ->
      # TODO: Or was this fixed?
      target.stat('hp')
    @afterSuccessfulHit = (battle, user, target, damage) ->
      # TODO: Is this message displayed even if the Pokemon survives?
      battle.message "It was a one-hit KO!"
    @chanceToHit = (battle, user, target) ->
      (user.level - target.level) + 30

makeRecoveryMove = (name) ->
  extendMove name, ->
    @use = (battle, user, target) ->
      hpStat = target.stat('hp')
      if target.currentHP == hpStat
        @fail(battle)
        return false
      amount = Math.round(hpStat / 2)
      battle.message "#{target.name} recovered #{amount} HP!"
      target.damage(-amount)

makeBasePowerBoostMove = (name, rawBasePower, maxBasePower, what) ->
  extendMove name, ->
    @basePower = (battle, user, target) ->
      pokemon = {user, target}[what]
      # NOTE: the 20 is hardcoded; perhaps this will change later?
      power = rawBasePower + 20 * pokemon.positiveBoostCount()
      Math.min(power, maxBasePower)

makeWeatherRecoveryMove = (name) ->
  extendMove name, ->
    @use = (battle, user, target) ->
      amount = if battle.hasWeather(Weather.NONE)
        util.roundHalfDown(target.stat('hp') / 2)
      else if battle.hasWeather(Weather.SUN)
        util.roundHalfDown(target.stat('hp') * 2 / 3)
      else
        util.roundHalfDown(target.stat('hp') / 4)
      battle.message "#{target.name} recovered #{amount} HP!"
      target.damage(-amount)

makeTrickMove = (name) ->
  extendMove name, ->
    @use = ->

    @afterSuccessfulHit = (battle, user, target) ->
      if !user.hasTakeableItem() || !target.hasTakeableItem()
        @fail(battle)
        return false
      uItem = user.getItem()
      tItem = target.getItem()
      user.setItem(tItem)
      target.setItem(uItem)

makeExplosionMove = (name) ->
  extendMove name, ->
    oldExecute = @execute
    @execute = (battle, user, targets) ->
      if !_.any(targets, (target) -> target.hasAbility('Damp'))
        user.faint()
        oldExecute.call(this, battle, user, targets)
      else
        battle.message "#{user.name} cannot use #{@name}!"

makeProtectCounterMove = (name, callback) ->
  extendMove name, ->
    @execute = (battle, user, targets) ->
      # Protect fails if the user is the last to move.
      if !battle.hasActionsLeft()
        user.unattach(Attachment.ProtectCounter)
        @fail(battle)
        return

      # Calculate and roll chance of success
      attachment = user.attach(Attachment.ProtectCounter)
      attachment.turns = 2
      chance = attachment.successChance()
      if battle.rng.randInt(1, chance, "protect") > 1
        user.unattach(Attachment.ProtectCounter)
        @fail(battle)
        return

      # Success!
      callback.call(this, battle, user, targets)

makeProtectMove = (name) ->
  makeProtectCounterMove name, (battle, user, targets) ->
    user.attach(Attachment.Protect)
    battle.message "#{user.name} protected itself!"

makeIdentifyMove = (name, type) ->
  extendMove name, ->
    @use = (battle, user, target) ->
      if target.attach(Attachment.Identify, {type})
        battle.message "#{target.name} was identified!"
      else
        @fail(battle)
        false

makeThiefMove = (name) ->
  extendMove name, ->
    @afterSuccessfulHit = (battle, user, target, damage) ->
      return  if user.hasItem() || !target.hasTakeableItem()
      battle.message "#{user.name} stole #{target.name}'s #{target.getItem().name}!"
      user.setItem(target.getItem())
      target.removeItem()

makeStatusCureMove = (name, message) ->
  extendMove name, ->
    @execute = (battle, user, targets) ->
      battle.message(message)
      for target in targets
        target.cureStatus()

makePickAttackMove = (name) ->
  extendMove name, ->
    @pickAttackStat = (user, target) ->
      target.stat('attack')

makePickDefenseMove = (name) ->
  extendMove name, ->
    @pickDefenseStat = (user, target) ->
      target.stat('defense')

makeDelayedAttackMove = (name, message) ->
  extendMove name, ->
    @execute = (battle, user, targets) ->
      # These moves pick a single target.
      target = targets[0]
      {team} = battle.getOwner(target)
      if !team.attach(Attachment.DelayedAttack, user: user, move: this)
        @fail(battle)
        return
      battle.message message.replace(/$1/, user.name)

makeRandomSwitchMove = (name) ->
  extendMove name, ->
    @afterSuccessfulHit = (battle, user, target, damage) ->
      return  if target.shouldPhase(battle, user) == false
      opponent = battle.getOwner(target)
      benched  = opponent.team.getAliveBenchedPokemon()
      return  if benched.length == 0
      pokemon = battle.rng.choice(benched)
      index = opponent.team.indexOf(pokemon)
      opponent.switch(0, index)

makeRampageMove = (moveName) ->
  extendMove moveName, ->
    @afterSuccessfulHit = (battle, user, target) ->
      user.attach(Attachment.Rampage, move: this)

makeRampageMove("Outrage")
makeRampageMove("Petal Dance")
makeRampageMove("Thrash")

# TODO: Does it fail if using twice, but on a different target?
# From PokemonLab:
# TODO: Major research is required here. Does Lock On make the next move to
#       target the subject hit; the next move to target the subject on the
#       next turn; all moves targeting the subject on the turn turn; or some
#       other possibility?
makeLockOnMove = (name) ->
  extendMove name, ->
    @use = (battle, user, target) ->
      if user.attach(Attachment.LockOn, {target})
        battle.message "#{user.name} locked onto #{target.name}."
      else
        @fail(battle)
        return false

makeStompMove = (name) ->
  extendMove name, ->
    @basePower = (battle, user, target) ->
      if target.has(Attachment.Minimize)
        2 * @power
      else
        @power

makeMeanLookMove = (name) ->
  extendMove name, ->
    @afterSuccessfulHit = (battle, user, target) ->
      if target.attach(Attachment.MeanLook)
        battle.message "#{target.name} can no longer escape!"
      else
        @fail(battle)
        return false

makeChargeMove = (name, args...) ->
  condition = args.pop()  if typeof args[args.length - 1] == 'function'
  message = args.pop()
  vulnerable = args.pop()  if args.length > 0

  extendMove name, ->
    @beforeTurn = (battle, user) ->
      data = {vulnerable, message, condition}
      data.move = this
      user.attach(Attachment.Charging, data)

makeChargeMove 'Skull Bash', "$1 tucked in its head!"
makeChargeMove 'Razor Wind', "$1 whipped up a whirlwind!"
makeChargeMove 'Sky Attack', "$1 became cloaked in a harsh light!"
makeChargeMove 'Shadow Force', [], "$1 vanished instantly!"
makeChargeMove 'Ice Burn', [], "$1 became cloaked in freezing air!"
makeChargeMove 'Freeze Shock', [], "$1 became cloaked in a freezing light!"
makeChargeMove 'Fly', ["Gust", "Thunder", "Twister", "Sky Uppercut", "Hurricane", "Smack Down", "Whirlwind"], "$1 flew up high!"
makeChargeMove 'Bounce', ["Gust", "Thunder", "Twister", "Sky Uppercut", "Hurricane", "Smack Down", "Whirlwind"], "$1 sprang up!"
makeChargeMove 'Dig', ["Earthquake", "Magnitude"], "$1 burrowed its way under the ground!"
makeChargeMove 'Dive', ["Surf", "Whirlpool"], "$1 hid underwater!"
makeChargeMove 'SolarBeam', "$1 absorbed light!", (battle) ->
  battle.hasWeather(Weather.SUN)

extendMove 'SolarBeam', ->
  @basePower = (battle, user, target) ->
    if battle.hasWeather(Weather.RAIN) || battle.hasWeather(Weather.SAND) ||
        battle.hasWeather(Weather.HAIL)
      @power >> 1
    else
      @power


makeRechargeMove = (name) ->
  extendMove name, ->
    @afterSuccessfulHit = (battle, user, target) ->
      user.attach(Attachment.Recharge)

makeMomentumMove = (name) ->
  extendMove name, ->
    @afterSuccessfulHit = (battle, user, target) ->
      attachment = user.attach(Attachment.Momentum, move: this)
      attachment.turns += 1

    @basePower = (battle, user, target) ->
      times = user.get(Attachment.Momentum)?.layers || 0
      bp = @power * Math.pow(2, times)
      bp *= 2  if user.has(Attachment.DefenseCurl)
      bp

makeRevengeMove = (moveName) ->
  extendMove moveName, ->
    @basePower = (battle, user, target) ->
      hit = user.lastHitBy
      return @power  if !hit?
      {pokemon, move, turn} = hit
      if target == pokemon && !move.isNonDamaging() && battle.turn == turn
        2 * @power
      else
        @power

makeBoostMove = (name, boostTarget, boosts) ->
  extendMove name, ->
    @use = (battle, user, target) ->
      pokemon = (if boostTarget == 'self' then user else target)
      pokemon.boost(boosts)

makeWeatherMove = (name, weatherType) ->
  extendMove name, ->
    @execute = (battle, user) ->
      length = 5
      length = 8  if weatherType == user.getItem()?.lengthensWeather
      battle.setWeather(weatherType, length)

extendWithBoost = (name, boostTarget, boosts) ->
  extendMove name, ->
    @afterSuccessfulHit = (battle, user, target) ->
      user.boost(boosts)

extendWithSecondaryBoost = (name, boostTarget, chance, boosts) ->
  extendMove name, ->
    @afterSuccessfulHit = (battle, user, target, damage) ->
      if battle.rng.next('secondary boost') >= chance
        return
      pokemon = (if boostTarget == 'self' then user else target)
      pokemon.boost(boosts)

makeCounterMove = (name, multiplier, applies) ->
  extendMove name, ->
    @getTargets = (battle, user) ->
      # Return the last pokemon who hit this one, if it's alive.
      pokemon = user.lastHitBy?.pokemon
      return [ pokemon ]  if pokemon? && !pokemon.isFainted()
  
      # Return a random target (or none).
      pokemon = battle.getOpponents(user)
      pokemon = pokemon.filter((p) -> !p.isFainted())
      if pokemon.length == 0
        []
      else
        [ battle.rng.choice(pokemon) ]

    @calculateDamage = -> 0
  
    @afterSuccessfulHit = (battle, user, target) ->
      hit = user.lastHitBy
      if hit? && applies(hit.move) && hit.turn == battle.turn
        target.damage(multiplier * hit.damage)
      else
        @fail(battle)

makeTrappingMove = (name) ->
  extendMove name, ->
    @afterSuccessfulHit = (battle, user, target, damage) ->
      unless target.has(Attachment.Trap)
        turns = if !user.hasItem("Grip Claw")
          battle.rng.randInt(4, 5, "trapping move")
        else
          7

        target.attach(Attachment.Trap, user: user, moveName: name, turns: turns)
        user.attach(Attachment.TrapLeash, {target})

extendWithDrain 'Absorb'
extendWithSecondaryBoost 'Acid', 'target', .1, specialDefense: -1
makeBoostMove 'Acid Armor', 'self', defense: 2
makeBoostMove 'Acid Spray', 'target', specialDefense: -2
makeBoostMove 'Agility', 'self', speed: 2
makeBoostMove 'Amnesia', 'self', specialDefense: 2
extendWithSecondaryBoost 'AncientPower', 'self', .1, {
  attack: 1, defense: 1, speed: 1, specialAttack: 1, specialDefense: 1
}
makeStatusCureMove 'Aromatherapy', 'A soothing aroma wafted through the area!'

extendMove 'Attract', ->
  @afterSuccessfulHit = (battle, user, target) ->
    if target.has(Attachment.Attract) ||
        (!(user.gender == 'M' && target.gender == 'F') &&
         !(user.gender == 'F' && target.gender == 'M'))
      @fail(battle)
      return
    target.attach(Attachment.Attract, source: user)

extendWithSecondaryBoost 'Aurora Beam', 'target', .1, attack: -1
makeBoostMove 'Autotomize', 'self', speed: 2
makeBoostMove 'Barrier', 'self', defense: 2

extendMove 'Baton Pass', ->
  @execute = (battle, user, targets) ->
    {team} = battle.getOwner(user)
    slot = team.indexOf(user)
    if !battle.forceSwitch(user)
      @fail(battle)
      return

    # Copy!
    passable = user.attachments.getPassable()
    stages = _.clone(user.stages)
    attachments = user.attachments.attachments
    attachments = attachments.filter((a) -> a.constructor in passable)
    for attachment in passable
      user.unattach(attachment)
    team.attach(Attachment.BatonPass, {slot, stages, attachments})

makeTrappingMove "Bind"
makeRechargeMove 'Blast Burn'
extendWithSecondaryStatus 'Blaze Kick', .1, Status.Burn
extendWithSecondaryStatus 'Blizzard', .1, Status.Freeze
makeMeanLookMove 'Block'
extendWithSecondaryStatus 'Blue Flare', .2, Status.Burn
extendWithSecondaryStatus 'Body Slam', .3, Status.Paralyze
extendWithSecondaryStatus 'Bolt Strike', .2, Status.Paralyze
extendWithSecondaryEffect 'Bone Club', .1, Attachment.Flinch
extendWithSecondaryStatus 'Bounce', .3, Status.Paralyze
extendWithSecondaryBoost 'Bubble', 'target', .1, speed: -1
extendWithSecondaryBoost 'BubbleBeam', 'target', .1, speed: -1
extendWithSecondaryBoost 'Bug Buzz', 'target', .1, specialDefense: -1
makeBoostMove 'Bulk Up', 'self', attack: 1, defense: 1
extendWithBoost 'Bulldoze', 'target', speed: -1
makeBoostMove 'Calm Mind', 'self', specialAttack: 1, specialDefense: 1

extendMove 'Camouflage', ->
  @use = (battle, user, target) ->
    # Camouflage changes type based on terrain
    # In Wi-Fi battles, the terrain always results in Ground type.
    target.types = [ "Ground" ]

extendMove 'Captivate', ->
  oldUse = @use
  @use = (battle, user, target) ->
    if (!(user.gender == 'M' && target.gender == 'F') &&
        !(user.gender == 'F' && target.gender == 'M'))
      @fail(battle)
    else
      target.boost(specialAttack: -2)

makeBoostMove 'Charge', 'self', specialDefense: 1
extendMove 'Charge', ->
  oldUse = @use
  @use = (battle, user, target) ->
    user.unattach(Attachment.Charge)  # Charge can be used twice in a row
    user.attach(Attachment.Charge)
    battle.message "#{user.name} began charging power!"
    oldUse.call(this, battle, user, target)

makeBoostMove 'Charm', 'target', attack: -2
extendWithSecondaryEffect 'Chatter', 1, Attachment.Confusion
extendWithSecondaryBoost 'Charge Beam', 'self', .7, specialAttack: 1

extendMove 'Chip Away', ->
  oldExecute = @execute
  @execute = (battle, user, targets) ->
    target.attach(Attachment.ChipAway)  for target in targets
    oldExecute.call(this, battle, user, targets)
    target.unattach(Attachment.ChipAway)  for target in targets

makeRandomSwitchMove "Circle Throw"
makeTrappingMove "Clamp"

extendMove 'Clear Smog', ->
  @afterSuccessfulHit = (battle, user, target) ->
    target.resetBoosts()
    battle.message "#{target.name}'s stat changes were removed!"

extendWithBoost 'Close Combat', 'self', defense: -1, specialDefense: -1
makeBoostMove 'Coil', 'self', attack: 1, defense: 1, accuracy: 1
extendWithPrimaryEffect 'Confuse Ray', Attachment.Confusion
extendWithSecondaryEffect 'Confusion', .1, Attachment.Confusion
extendWithSecondaryBoost 'Constrict', 'target', .1, speed: -1

extendMove 'Conversion', ->
  @use = (battle, user, target) ->
    {types, moves} = target
    moves = _.without(moves, battle.getMove(@name))
    # The original type of the move is used, not its generated type.
    moveTypes = moves.map((move) -> move.type)
    types = _.difference(moveTypes, types)
    type = battle.rng.choice(types, "conversion types")
    if !type?
      @fail(battle)
      return false
    target.types = [ type ]

extendMove 'Conversion 2', ->
  @use = (battle, user, target) ->
    {lastMove} = target
    if !lastMove?
      @fail(battle)
      return false

    moveType = lastMove.type
    possibles = []
    for type, value of util.Type
      possibles.push(type)  if util.typeEffectiveness(moveType, [ type ]) < 1
    user.types = [ battle.rng.choice(possibles, "conversion 2") ]

makeBoostMove 'Cosmic Power', 'self', defense: 1, specialDefense: 1
makeBoostMove 'Cotton Guard', 'self', defense: 3
makeBoostMove 'Cotton Spore', 'target', speed: -2
makeThiefMove 'Covet'
extendWithSecondaryBoost 'Crunch', 'target', .2, defense: -1
extendWithSecondaryBoost 'Crush Claw', 'target', .5, defense: -1
extendWithSecondaryEffect 'Dark Pulse', .2, Attachment.Flinch
extendWithPrimaryStatus 'Dark Void', Status.Sleep
makeBoostMove 'Defend Order', 'self', defense: 1, specialDefense: 1
makeBoostMove 'Defense Curl', 'self', defense: 1

extendMove 'Defense Curl', ->
  oldUse = @use
  @use = (battle, user, target) ->
    oldUse.call(this, battle, user, target)
    target.attach(Attachment.DefenseCurl)

makeProtectMove 'Detect'
extendWithSecondaryStatus 'Discharge', .3, Status.Paralyze
extendWithSecondaryEffect 'Dizzy Punch', .2, Attachment.Confusion
makeBoostMove 'Double Team', 'self', evasion: 1
makeBoostMove 'Dragon Dance', 'self', attack: 1, speed: 1
extendWithSecondaryEffect 'Dragon Rush', .2, Attachment.Flinch
extendWithSecondaryStatus 'DragonBreath', .3, Status.Paralyze
extendWithDrain 'Drain Punch'
extendWithDrain 'Dream Eater'
extendWithBoost 'Draco Meteor', 'self', specialAttack: -2
makeRandomSwitchMove "Dragon Tail"
extendWithSecondaryEffect 'DynamicPunch', 1, Attachment.Confusion
extendWithSecondaryBoost 'Earth Power', 'target', .1, specialDefense: -1
extendWithBoost 'Electroweb', 'target', speed: -1
extendWithSecondaryBoost 'Energy Ball', 'target', .1, specialDefense: -1

extendMove 'Embargo', ->
  @afterSuccessfulHit = (battle, user, target, damage) ->
    target.attach(Attachment.Embargo)
    battle.message "#{target.name} can't use items anymore!"

extendWithSecondaryStatus 'Ember', .1, Status.Burn
makeEruptionMove 'Eruption'
makeExplosionMove 'Explosion'
extendWithSecondaryEffect 'Extrasensory', .1, Attachment.Flinch
makeBoostMove 'Fake Tears', 'target', specialDefense: -2
extendWithSecondaryEffect 'Fake Out', 1, Attachment.Flinch

extendMove 'Fake Out', ->
  oldUse = @use
  @use = (battle, user, target) ->
    return false  if oldUse.call(this, battle, user, target) == false
    if user.turnsActive > 1
      @fail(battle)
      return false

makeBoostMove 'FeatherDance', 'target', attack: -2

extendMove 'Feint', ->
  @afterSuccessfulHit = (battle, user, target, damage) ->
    # TODO: Wide Guard
    if target.has(Attachment.Protect)
      target.unattach(Attachment.Protect)
      battle.message "#{target.name} fell for the feint!"

extendWithSecondaryBoost 'Fiery Dance', 'self', .5, specialAttack: 1
extendWithSecondaryStatus 'Fire Blast', .1, Status.Burn
extendWithFangEffect 'Fire Fang', .1, Status.Burn
extendWithSecondaryStatus 'Fire Punch', .1, Status.Burn
makeTrappingMove "Fire Spin"
makeOneHitKOMove 'Fissure'
makeReversalMove 'Flail'
extendWithBoost 'Flame Charge', 'self', speed: 1
extendMove 'Flame Wheel', -> @thawsUser = true
extendWithSecondaryStatus 'Flame Wheel', .1, Status.Burn
extendWithSecondaryStatus 'Flamethrower', .1, Status.Burn
extendMove 'Flare Blitz', -> @thawsUser = true
extendWithSecondaryStatus 'Flare Blitz', .1, Status.Burn
extendWithSecondaryBoost 'Flash Cannon', 'target', .1, specialDefense: -1
extendWithSecondaryStatus 'Force Palm', .3, Status.Paralyze
extendWithSecondaryBoost 'Focus Blast', 'target', .1, specialDefense: -1

extendMove 'Focus Energy', ->
  @use = (battle, user, target) ->
    if user.attach(Attachment.FocusEnergy)
      # TODO: Real message
      battle.message "#{user.name} began to focus!"
    else
      @fail(battle)
      false

extendMove 'Focus Punch', ->
  @beforeTurn = (battle, user) ->
    user.attach(Attachment.FocusPunch)

makeIdentifyMove("Foresight", "Normal")
makePickAttackMove 'Foul Play'
extendWithSecondaryStatus 'Freeze Shock', .3, Status.Paralyze
makeRechargeMove 'Frenzy Plant'
extendMove 'Fusion Flare', -> @thawsUser = true
extendWithDrain 'Giga Drain'
makeRechargeMove 'Giga Impact'
extendWithBoost 'Glaciate', 'target', speed: -1
makeWeightBased 'Grass Knot'
extendWithPrimaryStatus 'GrassWhistle', Status.Sleep
makeBoostMove 'Growl', 'target', attack: -1
makeBoostMove 'Growth', 'self', attack: 1, specialAttack: 1

extendMove 'Grudge', ->
  @execute = (battle, user, targets) ->
    user.attach(Attachment.Grudge)
    battle.message "#{user.name} wants its target to bear a grudge!"

makeOneHitKOMove 'Guillotine'
extendWithSecondaryStatus 'Gunk Shot', .3, Status.Poison
extendWithBoost 'Hammer Arm', 'self', speed: -1
makeBoostMove 'Harden', 'self', defense: 1
extendWithSecondaryEffect 'Headbutt', .3, Attachment.Flinch
makeStatusCureMove 'Heal Bell', 'A bell chimed!'
makeRecoveryMove 'Heal Order'
makeRecoveryMove 'Heal Pulse'
extendWithSecondaryEffect 'Heart Stamp', .3, Attachment.Flinch
makeWeightRatioBased 'Heat Crash'
extendWithSecondaryStatus 'Heat Wave', .1, Status.Burn
makeWeightRatioBased 'Heavy Slam'
makeJumpKick 'Hi Jump Kick'
makeBoostMove 'Hone Claws', 'self', attack: 1, accuracy: 1
makeOneHitKOMove 'Horn Drill'
extendWithDrain 'Horn Leech'
makeBoostMove 'Howl', 'self', attack: 1
makeRechargeMove 'Hydro Cannon'
makeRechargeMove 'Hyper Beam'
extendWithPrimaryStatus 'Hypnosis', Status.Sleep
makeMomentumMove 'Ice Ball'
extendWithBoost 'Icy Wind', 'target', speed: -1
makeBoostMove 'Iron Defense', 'self', defense: 2
extendWithSecondaryBoost 'Iron Tail', 'target', .1, defense: -1
makeWeatherMove 'Hail', Weather.HAIL
extendWithSecondaryEffect 'Hurricane', .3, Attachment.Confusion
extendWithSecondaryEffect 'Hyper Fang', .1, Attachment.Flinch
extendWithSecondaryStatus 'Ice Beam', .1, Status.Freeze
extendWithSecondaryStatus 'Ice Burn', .3, Status.Burn
extendWithFangEffect 'Ice Fang', .1, Status.Freeze
extendWithSecondaryStatus 'Ice Punch', .3, Status.Freeze
extendWithSecondaryEffect 'Icicle Crash', .3, Attachment.Flinch
extendWithSecondaryEffect 'Iron Head', .3, Attachment.Flinch
makeJumpKick 'Jump Kick'
extendWithSecondaryStatus 'Lava Plume', .3, Status.Burn
extendWithBoost 'Leaf Storm', 'self', specialAttack: -2
extendWithSecondaryBoost 'Leaf Tornado', 'target', .3, accuracy: -1
makeBoostMove 'Leer', 'target', defense: -1
extendWithDrain 'Leech Life'

extendMove 'Leech Seed', ->
  oldWillMiss = @willMiss
  @willMiss = (battle, user, target) ->
    if target.hasType("Grass")
      true
    else
      oldWillMiss.call(this, battle, user, target)

  @afterSuccessfulHit = (battle, user, target, damage) ->
    {team} = battle.getOwner(user)
    slot   = team.indexOf(user)
    target.attach(Attachment.LeechSeed, {team, slot})
    battle.message "#{target.name} was seeded!"

extendWithSecondaryStatus 'Lick', .3, Status.Paralyze
makeLockOnMove 'Lock-On'
makeWeightBased 'Low Kick'
extendWithBoost 'Low Sweep', 'target', speed: -1
extendWithPrimaryStatus 'Lovely Kiss', Status.Sleep

extendMove 'Lucky Chant', ->
  @afterSuccessfulHit = (battle, user, target) ->
    player = battle.getOwner(target)
    if player.team.attach(Attachment.LuckyChant)
      battle.message "The Lucky Chant shielded #{player.id}'s " +
                     "team from critical hits!"
    else
      @fail(battle)

makeTrappingMove "Magma Storm"
makeMeanLookMove 'Mean Look'
makeBoostMove 'Meditate', 'self', attack: 1
extendWithDrain 'Mega Drain'
extendWithSecondaryBoost 'Metal Claw', 'self', .1, attack: 1
makeBoostMove 'Metal Sound', 'target', specialDefense: -2
makeRecoveryMove 'Milk Drink'
makeLockOnMove 'Mind Reader'

extendMove 'Minimize', ->
  @use = (battle, user, target) ->
    target.attach(Attachment.Minimize)
    target.boost(evasion: 2)

makeIdentifyMove("Miracle Eye", "Psychic")

extendMove 'Mirror Move', ->
  @execute = (battle, user, targets) ->
    target = targets[0]
    move = target.lastMove
    if !move? || !move.hasFlag("mirror")
      @fail(battle)
      return false
    move.execute(battle, user, targets)

extendWithSecondaryBoost 'Mirror Shot', 'target', .3, accuracy: -1
extendWithSecondaryBoost 'Mist Ball', 'target', .5, specialAttack: -1
makeWeatherRecoveryMove 'Moonlight'
makeWeatherRecoveryMove 'Morning Sun'
extendWithSecondaryBoost 'Mud Bomb', 'target', .3, accuracy: -1
extendWithBoost 'Mud Shot', 'target', speed: -1
extendWithBoost 'Mud-Slap', 'target', accuracy: -1
extendWithSecondaryBoost 'Muddy Water', 'target', .3, accuracy: -1
makeBoostMove 'Nasty Plot', 'self', specialAttack: 2
extendWithSecondaryEffect 'Needle Arm', .3, Attachment.Flinch
extendWithSecondaryBoost 'Night Daze', 'target', .4, accuracy: -1
makeLevelAsDamageMove 'Night Shade'
extendWithSecondaryBoost 'Octazooka', 'target', .5, accuracy: -1
makeIdentifyMove("Odor Sleuth", "Normal")
extendWithSecondaryBoost 'Ominous Wind', 'self', .1, {
  attack: 1, defense: 1, speed: 1, specialAttack: 1, specialDefense: 1
}
extendWithBoost 'Overheat', 'self', specialAttack: -2
extendWithSecondaryStatus 'Poison Fang', .3, Status.Toxic
extendWithPrimaryStatus 'Poison Gas', Status.Poison
extendWithSecondaryStatus 'Poison Jab', .3, Status.Poison
extendWithPrimaryStatus 'PoisonPowder', Status.Poison
extendWithSecondaryStatus 'Poison Sting', .3, Status.Poison
extendWithSecondaryStatus 'Poison Tail', .1, Status.Poison
extendWithSecondaryStatus 'Powder Snow', .1, Status.Freeze
makeProtectMove 'Protect'
extendWithSecondaryEffect 'Psybeam', .1, Attachment.Confusion
extendWithSecondaryBoost 'Psychic', 'target', .1, specialDefense: -1
extendWithBoost 'Psycho Boost', 'self', specialAttack: -2
makePickDefenseMove 'Psyshock'
makePickDefenseMove 'Psystrike'
makeBasePowerBoostMove 'Punishment', 60, 200, 'target'
makeBoostMove 'Quiver Dance', 'self', specialAttack: 1, specialDefense: 1, speed: 1
makeWeatherMove 'Rain Dance', Weather.RAIN
extendWithSecondaryBoost 'Razor Shell', 'target', .5, defense: -1
makeRecoveryMove 'Recover'
extendWithSecondaryStatus 'Relic Song', .1, Status.Sleep
makeRevengeMove 'Revenge'
makeReversalMove 'Reversal'
makeRandomSwitchMove "Roar"
makeRechargeMove 'Roar of Time'
extendWithSecondaryEffect 'Rock Climb', .2, Attachment.Confusion
makeBoostMove 'Rock Polish', 'self', speed: 2
extendWithSecondaryBoost 'Rock Smash', 'target', .5, defense: -1
extendWithBoost 'Rock Tomb', 'target', speed: -1
extendWithSecondaryEffect 'Rock Slide', .3, Attachment.Flinch
makeRechargeMove 'Rock Wrecker'
extendWithSecondaryEffect 'Rolling Kick', .3, Attachment.Flinch
makeMomentumMove 'Rollout'
makeRecoveryMove 'Roost'
extendMove 'Roost', ->
  @afterSuccessfulHit = (battle, user, target, damage) ->
    user.attach(Attachment.Roost)

extendWithBoost 'Sand-Attack', 'target', accuracy: -1
extendMove 'Sacred Fire', -> @thawsUser = true
extendWithSecondaryStatus 'Sacred Fire', .5, Status.Burn
makeWeatherMove 'Sandstorm', Weather.SAND
makeTrappingMove "Sand Tomb"
extendMove 'Scald', -> @thawsUser = true
extendWithSecondaryStatus 'Scald', .3, Status.Burn
makeBoostMove 'Scary Face', 'target', speed: -2
makeBoostMove 'Screech', 'target', defense: -2
extendWithSecondaryStatus 'Searing Shot', .3, Status.Burn
makePickDefenseMove 'Secret Sword'
extendWithSecondaryBoost 'Seed Flare', 'target', .4, specialDefense: -2
makeExplosionMove 'Selfdestruct'
makeLevelAsDamageMove 'Seismic Toss'
extendWithSecondaryBoost 'Shadow Ball', 'target', .2, specialDefense: -1
makeBoostMove 'Sharpen', 'self', attack: 1
makeOneHitKOMove 'Sheer Cold'
makeBoostMove 'Shell Smash', 'self', {
  attack: 2, specialAttack: 2, speed: 2, defense: -1, specialDefense: -1
}
makeBoostMove 'Shift Gear', 'self', speed: 2, attack: 1
extendWithSecondaryEffect 'Signal Beam', .1, Attachment.Confusion
extendWithSecondaryBoost 'Silver Wind', 'self', .1, {
  attack: 1, defense: 1, speed: 1, specialAttack: 1, specialDefense: 1
}
extendWithPrimaryStatus 'Sing', Status.Sleep
makeBoostMove 'Skull Bash', 'self', defense: 1
extendWithSecondaryEffect 'Sky Attack', .3, Attachment.Flinch
makeRecoveryMove 'Slack Off'
extendWithPrimaryStatus 'Sleep Powder', Status.Sleep
extendWithSecondaryStatus 'Sludge', .3, Status.Poison
extendWithSecondaryStatus 'Sludge Bomb', .3, Status.Poison
extendWithSecondaryStatus 'Sludge Wave', .1, Status.Poison
extendWithSecondaryStatus 'Smog', .4, Status.Poison
makeBoostMove 'SmokeScreen', 'target', accuracy: -1
extendWithBoost 'Snarl', 'target', specialAttack: -1
extendWithSecondaryEffect 'Snore', .3, Attachment.Flinch
makeRecoveryMove 'Softboiled'
extendWithSecondaryStatus 'Spark', .3, Status.Paralyze
makeMeanLookMove 'Spider Web'

extendMove 'Spit Up', ->
  oldUse = @use
  @use = (battle, user, target) ->
    if !user.has(Attachment.Stockpile)
      @fail(battle)
      return false
    oldUse.call(this, battle, user, target)

  @basePower = (battle, user, target) ->
    attachment = user.get(Attachment.Stockpile)
    layers = attachment?.layers || 0
    100 * layers

  oldExecute = @execute
  @execute = (battle, user, targets) ->
    oldExecute.call(this, battle, user, targets)
    attachment = user.get(Attachment.Stockpile)
    return  if !attachment?
    num = -attachment.layers
    user.unattach(Attachment.Stockpile)
    user.boost(defense: num, specialDefense: num)

extendWithPrimaryStatus 'Spore', Status.Sleep
extendWithSecondaryEffect 'Steamroller', .3, Attachment.Flinch
makeStompMove 'Steamroller'
extendWithSecondaryBoost 'Steel Wing', 'self', .1, defense: 1

extendMove 'Stockpile', ->
  @afterSuccessfulHit = (battle, user, target) ->
    if user.attach(Attachment.Stockpile)
      user.boost(defense: 1, specialDefense: 1)
    else
      @fail(battle)

extendWithSecondaryEffect 'Stomp', .3, Attachment.Flinch
makeStompMove 'Stomp'
makeBasePowerBoostMove 'Stored Power', 20, 860, 'user'
makeBoostMove 'String Shot', 'target', speed: -1
extendWithBoost 'Struggle Bug', 'target', specialAttack: -1
extendWithPrimaryStatus 'Stun Spore', Status.Paralyze
makeWeatherMove 'Sunny Day', Weather.SUN
extendWithBoost 'Superpower', 'self', attack: -1, defense: -1
extendWithPrimaryEffect 'Supersonic', Attachment.Confusion

extendMove 'Swallow', ->
  oldUse = @use
  @use = (battle, user, target) ->
    if !user.has(Attachment.Stockpile)
      @fail(battle)
      return false
    oldUse.call(this, battle, user, target)

  @afterSuccessfulHit = (battle, user, target) ->
    {layers} = target.get(Attachment.Stockpile)
    amount = util.roundHalfDown(target.stat('hp') / Math.pow(2, 3 - layers))
    # Swallow is not a draining move, so it is not affected by Big Root.
    target.damage(-amount)

  oldExecute = @execute
  @execute = (battle, user, targets) ->
    oldExecute.call(this, battle, user, targets)
    for target in targets
      attachment = target.get(Attachment.Stockpile)
      return  if !attachment?
      num = -attachment.layers
      target.unattach(Attachment.Stockpile)
      user.boost(defense: num, specialDefense: num)

extendWithPrimaryEffect 'Sweet Kiss', Attachment.Confusion
makeBoostMove 'Sweet Scent', 'target', evasion: -1
makeTrickMove 'Switcheroo'
makeBoostMove 'Swords Dance', 'self', attack: 2
extendMove 'Super Fang', ->
  @calculateDamage = (battle, user, target) ->
    halfHP = Math.floor(target.currentHP / 2)
    Math.max(1, halfHP)
makeWeatherRecoveryMove 'Synthesis'
makeBoostMove 'Tail Glow', 'self', attack: 3
makeBoostMove 'Tail Whip', 'target', defense: -1
extendWithPrimaryEffect 'Teeter Dance', Attachment.Confusion
extendMove 'Teleport', (battle) ->
  @execute = -> @fail(battle)
makeThiefMove 'Thief'
extendWithSecondaryStatus 'Thunder', .3, Status.Paralyze
extendWithFangEffect 'Thunder Fang', .1, Status.Paralyze
extendWithPrimaryStatus 'Thunder Wave', Status.Paralyze
extendWithSecondaryStatus 'Thunderbolt', .1, Status.Paralyze
extendWithSecondaryStatus 'ThunderPunch', .1, Status.Paralyze
extendWithSecondaryStatus 'ThunderShock', .1, Status.Paralyze
makeBoostMove 'Tickle', 'target', attack: -1, defense: -1
extendWithPrimaryStatus 'Toxic', Status.Toxic
extendMove 'Tri Attack', ->
  oldFunc = @afterSuccessfulHit
  @afterSuccessfulHit = (battle, user, target, damage) ->
    oldFunc.call(this, battle, user, target, damage)
    return  if battle.rng.next("secondary status") >= .2
    switch battle.rng.randInt(0, 2, "tri attack effect")
      when 0 then target.attach(Status.Paralyze)
      when 1 then target.attach(Status.Burn)
      when 2 then target.attach(Status.Freeze)

makeTrickMove 'Trick'
# extendWithSecondaryEffect 'twineedle', .2, Status.Poison
extendWithSecondaryEffect 'Twister', .2, Attachment.Flinch
extendWithSecondaryBoost 'V-create', 'self', defense: -1, specialDefense: -1, speed: -1
extendWithSecondaryStatus 'Volt Tackle', .1, Status.Paralyze
extendWithSecondaryEffect 'Water Pulse', .2, Attachment.Confusion
makeEruptionMove 'Water Spout'
extendWithSecondaryEffect 'Waterfall', .2, Attachment.Flinch
makeRandomSwitchMove "Whirlwind"
extendWithPrimaryStatus 'Will-O-Wisp', Status.Burn
makeBoostMove 'Withdraw', 'user', defense: 1
makeBoostMove 'Work Up', 'user', attack: 1, specialAttack: 1
makeTrappingMove "Wrap"
extendWithSecondaryEffect 'Zen Headbutt', .2, Attachment.Flinch
extendWithSecondaryStatus 'Zap Cannon', 1, Status.Paralyze

extendMove 'Assist', ->
  bannedMoves =
    "Assist":       true
    "Bestow":       true
    "Chatter":      true
    "Circle Throw": true
    'Copycat':      true
    "Counter":      true
    "Covet":        true
    "Destiny Bond": true
    "Detect":       true
    "Dragon Tail":  true
    "Endure":       true
    "Feint":        true
    "Focus Punch":  true
    "Follow Me":    true
    "Helping Hand": true
    "Me First":     true
    "Metronome":    true
    "Mimic":        true
    "Mirror Coat":  true
    "Mirror Move":  true
    "Nature Power": true
    "Protect":      true
    "Rage Powder":  true
    "Sketch":       true
    "Sleep Talk":   true
    "Snatch":       true
    "Struggle":     true
    "Switcheroo":   true
    "Thief":        true
    "Transform":    true
    "Trick":        true
  @execute = (battle, user, targets) ->
    {team}  = battle.getOwner(user)
    pokemon = _.without(team.pokemon, user)
    moves   = _.flatten(pokemon.map((p) -> p.moves))
    moves   = moves.filter((move) -> move.name not of bannedMoves)
    if moves.length == 0
      @fail(battle)
    else
      move = battle.rng.choice(moves, "assist")
      # Assist chooses a random foe if selecting a Pokemon.
      if move.target == 'selected-pokemon'
        pokemon = battle.getOpponents(user)
        targets = [ battle.rng.choice(pokemon) ]
      else
        targets = battle.getTargets(move, user)
      move.execute(battle, user, targets)

extendMove 'Aqua Ring', ->
  @afterSuccessfulHit = (battle, user, target) ->
    target.attach(Attachment.AquaRing)
    battle.message "#{target.name} surrounded itself with a veil of water!"

extendMove 'Assurance', ->
  @basePower = (battle, user, target) ->
    hit = user.lastHitBy
    if hit?.turn == battle.turn && !hit.move.isNonDamaging()
      2 * @power
    else
      @power

extendMove 'Autotomize', ->
  @afterSuccessfulHit = (battle, user, target) ->
    target.attach(Attachment.Autotomize)

makeRevengeMove 'Avalanche'

extendMove 'Acrobatics', ->
  @basePower = (battle, user, target) ->
    if !user.hasItem() then 2 * @power else @power

extendMove 'Acupressure', ->
  @use = (battle, user, target) ->
    stats = (stat  for stat, num of target.stages when num < 6)
    if stats.length > 0
      randomStat = battle.rng.choice(stats)
      hash = {}
      hash[randomStat] = 2
      target.boost(hash)
    else
      @fail(battle)
      return false

# TODO:
# All Beat Up hits are boosted if the user of the move has an Attack-raising
# item such as Choice Band, but the attack ignores all stat changes from
# moves such as Swords Dance.
extendMove 'Beat Up', ->
  oldExecute = @execute
  @execute = (battle, user, targets) ->
    target.attach(Attachment.BeatUp)  for target in targets
    oldExecute.call(this, battle, user, targets)
    target.unattach(Attachment.BeatUp)  for target in targets

  oldUse = @use
  @use = (battle, user, target) ->
    {team} = battle.getOwner(user)
    attachment = target.get(Attachment.BeatUp)
    attachment.index++
    pokemon = team.at(attachment.index)
    while pokemon.hasStatus() || pokemon.isFainted()
      attachment.index++
      pokemon = team.at(attachment.index)
    oldUse.call(this, battle, user, target)

  @calculateNumberOfHits = (battle, user, target) ->
    {team} = battle.getOwner(user)
    team.pokemon.filter((p) -> !p.hasStatus() && !p.isFainted()).length

  @basePower = (battle, user, target) ->
    {team} = battle.getOwner(user)
    attachment = target.get(Attachment.BeatUp)
    {baseStats} = team.at(attachment.index)
    5 + Math.floor(baseStats.attack / 10)

extendMove 'Belly Drum', ->
  @use = (battle, user, target) ->
    halfHP = Math.floor(user.stat('hp') / 2)
    if user.currentHP > halfHP
      user.damage(halfHP)
      user.boost(attack: 12)
      battle.message "#{user.name} cut its own HP and maximized its Attack!"
    else
      @fail(battle)
      return false

extendMove 'Brick Break', ->
  oldUse = @use
  @use = (battle, user, target) ->
    return false  if oldUse.call(this, battle, user, target) == false
    {team} = battle.getOwner(target)
    team.unattach(Attachment.Reflect)
    team.unattach(Attachment.LightScreen)

extendMove 'Brine', ->
  @basePower = (battle, user, target) ->
    if target.currentHP <= Math.floor(target.stat('hp') / 2)
      2 * @power
    else
      @power

extendMove 'Bug Bite', ->
  @afterSuccessfulHit = (battle, user, target) ->
    item = target.getItem()
    if target.isAlive() && item?.type == 'berries'
      item.eat(battle, user)
      target.removeItem()

extendMove 'Copycat', ->
  @execute = (battle, user, targets) ->
    move = battle.lastMove
    if move? && move != battle.getMove('Copycat')
      battle.message "#{user.name} used #{move.name}!"
      move.execute(battle, user, targets)
    else
      @fail(battle)


makeCounterMove('Counter', 2, (move) -> move.isPhysical())
makeCounterMove('Mirror Coat', 2, (move) -> move.isSpecial())
makeCounterMove('Metal Burst', 1.5, (move) -> move.isPhysical() || move.isSpecial())

extendMove 'Crush Grip', ->
  @basePower = (battle, user, target) ->
    1 + Math.floor(120 * target.currentHP / target.stat('hp'))

extendMove 'Curse', ->
  @getTargets = (battle, user) ->
    pokemon = battle.getOpponents(user)
    [ battle.rng.choice(pokemon, "random opponent") ]

  @execute = (battle, user, targets) ->
    if !user.hasType("Ghost")
      user.boost(attack: 1, defense: 1, speed: -1)
      return

    user.damage Math.floor(user.stat('hp') / 2)
    for target in targets
      target.attach(Attachment.Curse)
      battle.message "#{user.name} cut its own HP and laid a curse on #{target.name}!"

extendMove 'Destiny Bond', ->
  @execute = (battle, user, targets) ->
    user.attach(Attachment.DestinyBond)
    battle.message "#{user.name} is trying to take its foe down with it!"

extendMove 'Disable', ->
  # TODO: Does it only reduce duration if the disabled pokemon successfully
  #       goes through with a move?
  oldUse = @use
  @use = (battle, user, target) ->
    # Fails if the target doesn't know the last move it used or if that move
    # has zero PP or if the target has not moved since it was active.
    move = target.lastMove
    if !move? || !target.knows(move) || target.pp(move) <= 0
      @fail(battle)
      return false

    oldUse.call(this, battle, user, target)

  @afterSuccessfulHit = (battle, user, target) ->
    move = target.lastMove
    target.attach(Attachment.Disable, {move})
    battle.message "#{target.name}'s #{move.name} was disabled!"

makeDelayedAttackMove("Doom Desire", "$1 chose Doom Desire as its destiny!")

extendMove 'Dragon Rage', ->
  @calculateDamage = (battle, user, target) ->
    40

extendMove 'Dream Eater', ->
  oldUse = @use
  @use = (battle, user, target) ->
    if !target.has(Status.Sleep)
      @fail(battle)
      return false
    oldUse.call(this, battle, user, target)

extendMove 'Echoed Voice', ->
  @basePower = (battle, user, target) ->
    layers = battle.get(Attachment.EchoedVoice)?.layers || 0
    @power * (layers + 1)

  @afterSuccessfulHit = (battle, user, target) ->
    battle.attach(Attachment.EchoedVoice)
    attachment = battle.get(Attachment.EchoedVoice)
    attachment.turns = 2

extendMove 'Encore', ->
  bannedMoves =
    'Encore': true
    'Mimic': true
    'Mirror Move': true
    'Sketch': true
    'Struggle': true
    'Transform': true
  @afterSuccessfulHit = (battle, user, target) ->
    if !target.lastMove?
      @fail(battle)
    else if target.lastMove.name of bannedMoves
      @fail(battle)
    else if target.pp(target.lastMove) == 0
      @fail(battle)
    else if target.attach(Attachment.Encore)
      if battle.willMove(target)
        battle.changeMove(target, target.lastMove)
    else
      @fail(battle)

extendMove 'Endeavor', ->
  oldUse = @use
  @use = (battle, user, target) ->
    return false  if oldUse.call(this, battle, user, target) == false
    if target.currentHP < user.currentHP
      @fail(battle)
      return false

  @calculateDamage = (battle, user, target) ->
    target.currentHP - user.currentHP

makeProtectCounterMove 'Endure', (battle, user, targets) ->
  battle.message "#{user.name} braced itself!"
  user.attach(Attachment.Endure)

extendMove 'Facade', ->
  @basePower = (battle, user, target) ->
    if user.hasStatus()
      2 * @power
    else
      @power

extendMove 'Final Gambit', ->
  @afterSuccessfulHit = (battle, user, target) ->
    user.faint()

  @calculateDamage = (battle, user, target) ->
    user.currentHP

extendMove 'Flatter', ->
  @afterSuccessfulHit = (battle, user, target) ->
    target.attach(Attachment.Confusion, {battle})
    target.boost(specialAttack: -2, user)

extendMove 'Fling', ->
  @beforeTurn = (battle, user) ->
    user.attach(Attachment.Fling)

  oldUse = @use
  @use = (battle, user, target) ->
    fling = user.get(Attachment.Fling)
    if !fling?.item
      @fail(battle)
      return false

    oldUse.call(this, battle, user, target)

  @afterSuccessfulHit = (battle, user, target) ->
    {item} = user.get(Attachment.Fling)
    switch item.name
      when "Poison Barb"
        target.attach(Status.Poison)
      when "Light Ball"
        target.attach(Status.Paralyze)
      when "Flame Orb"
        target.attach(Status.Burn)
      when "Toxic Orb"
        target.attach(Status.Toxic)
      when "King's Rock", "Razor Fang"
        target.attach(Attachment.Flinch)
      when "Mental Herb", "White Herb"
        item.activate(battle, target)
      else
        item.eat?(battle, target)  if item.type == "berries"

  @basePower = (battle, user, target) ->
    fling = user.get(Attachment.Fling)
    fling.item.flingPower

extendMove 'Frustration', ->
  @basePower = -> 102

extendMove 'Fury Cutter', ->
  @afterSuccessfulHit = (battle, user, target, damage) ->
    user.attach(Attachment.FuryCutter, move: this)

  @basePower = (battle, user, target) ->
    attachment = user.get(Attachment.FuryCutter)
    layers = attachment?.layers || 0
    @power * Math.pow(2, layers)

makeDelayedAttackMove("Future Sight", "$1 foresaw an attack!")

extendMove 'Gravity', ->
  @execute = (battle, user, targets) ->
    if !battle.attach(Attachment.Gravity)
      @fail(battle)
      return
    battle.message "Gravity intensified!"
    for target in targets
      target.attach(Attachment.GravityPokemon)
      target.unattach(Attachment.MagnetRise)
      target.unattach(Attachment.Telekinesis)
      charging = target.get(Attachment.Charging)
      target.unattach(Attachment.Charging)  if charging?.move.hasFlag("gravity")

extendMove 'Guard Swap', ->
  @afterSuccessfulHit = (battle, user, target) ->
    for stat in [ 'defense', 'specialDefense' ]
      stats = [ target.stages[stat], user.stages[stat] ]
      [ user.stages[stat], target.stages[stat] ] = stats

extendMove 'Gyro Ball', ->
  @basePower = (battle, user, target) ->
    power = 1 + Math.floor(25 * target.stat('speed') / user.stat('speed'))
    Math.min(150, power)

extendMove 'Haze', ->
  @execute = (battle, user, targets) ->
    user.resetBoosts()
    for target in targets
      target.resetBoosts()
    battle.message "All stat changes were eliminated!"

extendMove 'Heart Swap', ->
  @afterSuccessfulHit = (battle, user, target) ->
    [user.stages, target.stages] = [target.stages, user.stages]

extendMove 'Hex', ->
  @basePower = (battle, user, target) ->
    if target.hasStatus()
      2 * @power
    else
      @power

extendMove 'Hidden Power', ->
  @basePower = (battle, user, target) ->
    ivs =
      hp: user.iv('hp')
      attack: user.iv('attack')
      defense: user.iv('defense')
      speed: user.iv('speed')
      specialAttack: user.iv('specialAttack')
      specialDefense: user.iv('specialDefense')
    hiddenPower.BW.basePower(ivs)

  @getType = (battle, user, target) ->
    ivs =
      hp: user.iv('hp')
      attack: user.iv('attack')
      defense: user.iv('defense')
      speed: user.iv('speed')
      specialAttack: user.iv('specialAttack')
      specialDefense: user.iv('specialDefense')
    hiddenPower.BW.type(ivs)

extendMove 'Imprison', ->
  @execute = (battle, user, targets) ->
    # There is only one target for Imprison.
    target = targets[0]
    {moves} = target
    if target.attach(Attachment.Imprison, {battle, moves})
      battle.message "#{target.name} sealed the opponent's moves!"
    else
      @fail(battle)

extendMove 'Incinerate', ->
  @afterSuccessfulHit = (battle, user, target, damage) ->
    if target.hasItem() && target.getItem().type == 'berries'
      battle.message "#{target.name}'s #{target.getItem().name} was burnt up!"
      target.removeItem()

extendMove 'Ingrain', ->
  @afterSuccessfulHit = (battle, user, target) ->
    target.attach(Attachment.Ingrain)
    battle.message "#{target.name} planted its roots!"

extendMove 'Judgment', ->
  @getType = (battle, user, target) ->
    user.getItem()?.plate || @type

extendMove 'Knock Off', ->
  @afterSuccessfulHit = (battle, user, target, damage) ->
    if target.hasItem()
      battle.message "#{user.name} knocked off #{target.name}'s #{target.getItem().name}!"
      target.removeItem()

extendMove 'Last Resort', ->
  oldUse = @use
  @use = (battle, user, target) ->
    if this not in user.moves || user.moves.length <= 1
      @fail(battle)
      return false
    for moveName in _.without(user.moves, this).map((m) -> m.name)
      if moveName not of user.used
        @fail(battle)
        return false
    oldUse.call(this, battle, user, target)

extendMove 'Light Screen', ->
  @execute = (battle, user, opponents) ->
    {team} = battle.getOwner(user)
    if team.attach(Attachment.LightScreen, {user})
      battle.message "A screen came up!"
    else
      @fail(battle)

extendMove 'Healing Wish', ->
  @afterSuccessfulHit = (battle, user, target) ->
    {team} = battle.getOwner(target)
    if team.getAliveBenchedPokemon().length > 0
      target.faint()
      team.attach(Attachment.HealingWish)
    else
      @fail(battle)

extendMove 'Lunar Dance', ->
  @afterSuccessfulHit = (battle, user, target) ->
    {team} = battle.getOwner(target)
    if team.getAliveBenchedPokemon().length > 0
      target.faint()
      team.attach(Attachment.LunarDance)
    else
      @fail(battle)

extendMove 'Magic Coat', ->
  @afterSuccessfulHit = (battle, user, target) ->
    target.attach(Attachment.MagicCoat)

extendMove 'Magnet Rise', ->
  @use = (battle, user, target) ->
    if target.attach(Attachment.MagnetRise)
      battle.message "#{target.name} is now floating in the air!"
    else
      @fail(battle)
      return false

extendMove 'Magnitude', ->
  @basePower = (battle, user, target) ->
    rand = battle.rng.randInt(0, 99, "magnitude")
    magnitude = 0
    power = 0
    if rand < 5
      power = 10
      magnitude = 4
    else if rand < 15
      power = 30
      magnitude = 5
    else if rand < 35
      power = 50
      magnitude = 6
    else if rand < 65
      power = 70
      magnitude = 7
    else if rand < 85
      power = 90
      magnitude = 8
    else if rand < 95
      power = 110
      magnitude = 9
    else
      power = 150
      magnitude = 10

    battle.message "Magnitude #{magnitude}!"
    power

extendMove 'Me First', ->
  bannedMoves = {
    "Chatter"    : true
    "Counter"    : true
    "Covet"      : true
    "Focus Punch": true
    "Me First"   : true
    "Metal Burst": true
    "Mirror Coat": true
    "Struggle"   : true
    "Thief"      : true
  }
  @execute = (battle, user, targets) ->
    target = targets[0]  # Me First is a single-target move
    m = battle.peekMove(target)
    if !battle.willMove(target) || m.isNonDamaging() || bannedMoves[m.name]
      @fail(battle)
      return false
    user.attach(Attachment.MeFirst)
    m.execute(battle, user, targets)

extendMove 'Memento', ->
  oldExecute = @execute
  @execute = (battle, user, targets) ->
    user.faint()
    oldExecute.call(this, battle, user, targets)

  @afterSuccessfulHit = (battle, user, target) ->
    target.boost(attack: -2, specialAttack: -2, user)

extendMove 'Metronome', ->
  impossibleMoves =
    "After You": true
    "Assist": true
    "Bestow": true
    'Chatter': true
    "Copycat": true
    "Counter": true
    "Covet": true
    "Destiny Bond": true
    "Detect": true
    "Endure": true
    "Feint": true
    "Focus Punch": true
    "Follow Me": true
    "Freeze Shock": true
    "Helping Hand": true
    "Ice Burn": true
    "Me First": true
    "Mimic": true
    "Mirror Coat": true
    "Mirror Move": true
    "Nature Power": true
    "Protect": true
    "Quash": true
    "Quick Guard": true
    "Rage Powder": true
    "Relic Song": true
    "Secret Sword": true
    "Sketch": true
    "Sleep Talk": true
    "Snatch": true
    "Snarl": true
    "Snore": true
    "Struggle": true
    "Switcheroo": true
    "Techno Blast": true
    "Thief": true
    "Transform": true
    "Trick": true
    "V-create": true
    "Wide Guard": true

  for move of impossibleMoves
    if move not of Moves
      throw new Error("The illegal Metronome move '#{move}' does not exist.")

  @execute = (battle, user, targets) ->
    index = battle.rng.randInt(0, MoveList.length - 1, "metronome")
    while MoveList[index].name of impossibleMoves || MoveList[index] in user.moves
      index = battle.rng.randInt(0, MoveList.length - 1, "metronome reselect")
    move = MoveList[index]
    battle.message "Waggling a finger let it use #{move.name}!"

    # Determine new targets
    if move.target == 'selected-pokemon'
      pokemon = battle.getOpponents(user)
      targets = [ battle.rng.choice(pokemon) ]
    else
      targets = battle.getTargets(move, user)
    move.execute(battle, user, targets)

extendMove 'Nature Power', ->
  @execute = (battle, user, targets) ->
    # In Wi-Fi battles, Earthquake is always chosen.
    battle.message "#{@name} turned into Earthquake!"
    earthquake = battle.getMove('Earthquake')
    earthquake.execute(battle, user, targets)

  @getTargets = (battle, user) ->
    earthquake = battle.getMove('Earthquake')
    battle.getTargets(earthquake, user)

extendMove 'Nightmare', ->
  @afterSuccessfulHit = (battle, user, target) ->
    if target.has(Status.Sleep) && target.attach(Attachment.Nightmare)
      battle.message "#{target.name} began having a nightmare!"
    else
      @fail(battle)

extendMove 'Pain Split', ->
  @use = (battle, user, target) ->
    averageHP = Math.floor((user.currentHP + target.currentHP) / 2)
    user.setHP(averageHP)
    target.setHP(averageHP)
    battle.message "The battlers shared their pain!"

extendMove 'Pay Day', ->
  @afterSuccessfulHit = (battle, user, target) ->
    battle.message "Coins were scattered everywhere!"

extendMove 'Payback', ->
  @basePower = (battle, user, target) ->
    if !target.lastMove? || battle.willMove(target)
      @power
    else
      2 * @power

extendMove 'Power Swap', ->
  @afterSuccessfulHit = (battle, user, target) ->
    for stat in [ 'attack', 'specialAttack' ]
      stats = [ target.stages[stat], user.stages[stat] ]
      [ user.stages[stat], target.stages[stat] ] = stats

extendMove 'Present', ->
  @basePower = (battle, user, target) ->
    user.get(Attachment.Present).power

  @afterSuccessfulHit = (battle, user, target) ->
    if user.get(Attachment.Present).power == 0
      amount = target.stat('hp') >> 2
      target.damage(-amount)

  oldExecute = @execute
  @execute = (battle, user, targets) ->
    chance = battle.rng.next("present")
    power  = if chance < .1
               120
             else if chance < .3
               0
             else if chance < .6
               80
             else
               40
    user.attach(Attachment.Present, {power})
    oldExecute.call(this, battle, user, targets)

extendMove 'Psywave', ->
  @calculateDamage = (battle, user, target) ->
    fraction = battle.rng.randInt(5, 15, "psywave") / 10
    Math.floor(user.level * fraction)

extendMove 'Perish Song', ->
  oldExecute = @execute
  @execute = (battle, user, targets) ->
    oldExecute.call(this, battle, user, targets)
    battle.message "All Pokemon hearing the song will faint in three turns!"

  @afterSuccessfulHit = (battle, user, target) ->
    target.attach(Attachment.PerishSong)

extendMove 'Psych Up', ->
  @use = (battle, user, target) ->
    for stage, value of target.stages
      user.stages[stage] = value
    battle.message "#{user.name} copied #{target.name}'s stat changes!"

extendMove 'Psycho Shift', ->
  @afterSuccessfulHit = (battle, user, target) ->
    if !user.hasStatus() || target.hasStatus()
      @fail(battle)
      return false
    status = Status[user.status]
    user.cureStatus()
    target.attach(status)

extendMove 'Pursuit', ->
  @beforeTurn = (battle, user) ->
    user.attach(Attachment.Pursuit)

  @basePower = (battle, user, target) ->
    if user.has(Attachment.PursuitModifiers)
      2 * @power
    else
      @power

extendMove 'Rage', ->
  @afterSuccessfulHit = (battle, user, target) ->
    user.attach(Attachment.Rage)

extendMove 'Rapid Spin', ->
  @afterSuccessfulHit = (battle, user, target, damage) ->
    # Do not remove anything if the user is fainted.
    if user.isFainted()
      return

    owner = battle.getOwner(user)
    team = owner.team

    # Remove any entry hazards
    entryHazards = [Attachment.Spikes, Attachment.StealthRock, Attachment.ToxicSpikes]

    hazardRemoved = false
    for hazard in entryHazards
      if team.unattach(hazard)
        hazardRemoved = true

    if hazardRemoved
      battle.message "#{owner.id}'s side of the field is cleared of entry hazards."

    # Remove trapping moves like fire-spin
    trap = user.unattach(Attachment.Trap)
    battle.message "#{user.name} was freed from #{trap.moveName}!"  if trap

    # Remove leech seed
    leechSeed = user.unattach(Attachment.LeechSeed)
    battle.message "#{user.name} was freed from Leech Seed!"  if leechSeed

extendMove 'Reflect', ->
  @execute = (battle, user, opponents) ->
    {team} = battle.getOwner(user)
    if team.attach(Attachment.Reflect, {user})
      battle.message "A screen came up!"
    else
      @fail(battle)

extendMove 'Return', ->
  @basePower = -> 102

extendMove 'Smack Down', ->
  @afterSuccessfulHit = (battle, user, target) ->
    target.attach(Attachment.SmackDown)
    target.unattach(Attachment.MagnetRise)
    target.unattach(Attachment.Telekinesis)
    # Smack Down will miss on charge moves it cannot hit.
    target.unattach(Attachment.Charging)

makeStatusCureAttackMove 'SmellingSalt', Status.Paralyze

extendMove 'SonicBoom', ->
  @calculateDamage = (battle, user, target) ->
    20

extendMove 'Spikes', ->
  @execute = (battle, user, opponents) ->
    for opponent in opponents
      if opponent.attachToTeam(Attachment.Spikes)
        battle.message "#{@name} were scattered all around #{opponent.id}'s team's feet!"
      else
        @fail(battle)

extendMove 'Spite', ->
  @execute = (battle, user, opponents) ->
    for opponent in opponents
      move = opponent.lastMove
      if !move || !opponent.knows(move) || opponent.pp(move) == 0
        @fail(battle)
        return
      opponent.reducePP(move, 4)
      battle.message "It reduced the PP of #{opponent.name}!"

extendMove 'Stealth Rock', ->
  @execute = (battle, user, opponents) ->
    for opponent in opponents
      if opponent.attachToTeam(Attachment.StealthRock)
        battle.message "Pointed stones float in the air around #{opponent.id}'s team!"
      else
        @fail(battle)

extendMove 'Struggle', ->
  @type = '???'

  @typeEffectiveness = -> 1

  @afterSuccessfulHit = (battle, user, target) ->
    user.damage(user.stat('hp') >> 2)

extendMove 'Splash', ->
  @execute = (battle, user, target) ->
    battle.message "But nothing happened!"

extendMove 'Substitute', ->
  @execute = (battle, user, targets) ->
    dmg = user.stat('hp') >> 2
    if dmg >= user.currentHP || dmg == 0
      battle.message "It was too weak to make a substitute!"
      @fail(battle)
      return

    if !user.attach(Attachment.Substitute, hp: dmg, battle: battle)
      battle.message "#{user.name} already has a substitute!"
      @fail(battle)
      return

    user.damage(dmg)
    battle.message "#{user.name} put in a substitute!"
    user.tell(Protocol.MOVE_SUCCESS, user.team.indexOf(user))

  @fail = (battle) ->

extendMove 'Sucker Punch', ->
  oldUse = @use
  @use = (battle, user, target) ->
    if !battle.willMove(target)
      @fail(battle)
      return false
    else
      oldUse.call(this, battle, user, target)

extendMove 'Swagger', ->
  @afterSuccessfulHit = (battle, user, target) ->
    target.attach(Attachment.Confusion, {battle})
    target.boost(attack: -2, user)

extendMove 'Synchronoise', ->
  oldUse = @use
  @use = (battle, user, target) ->
    if _.every(user.types, (type) -> type not in target.types)
      @fail(battle)
      return false
    return oldUse.call(this, battle, user, target)

extendMove 'Taunt', ->
  @afterSuccessfulHit = (battle, user, target) ->
    if target.attach(Attachment.Taunt, battle)
      battle.message "#{target.name} fell for the taunt!"
    else
      @fail(battle)

extendMove 'Techno Blast', ->
  @getType = (battle, user, target) ->
    switch user.getItem()?.name
      when "Burn Drive"
        "Fire"
      when "Douse Drive"
        "Water"
      when "Shock Drive"
        "Electric"
      else
        "Normal"

extendMove 'Telekinesis', ->
  @afterSuccessfulHit = (battle, user, target) ->
    if target.attach(Attachment.Telekinesis)
      battle.message "#{target.name} was hurled into the air!"
    else
      @fail(battle)

extendMove 'Torment', ->
  @afterSuccessfulHit = (battle, user, target) ->
    if target.attach(Attachment.Torment)
      battle.message "#{target.name} was subjected to torment!"
    else
      @fail(battle)

extendMove 'Toxic Spikes', ->
  @execute = (battle, user, opponents) ->
    for opponent in opponents
      if opponent.attachToTeam(Attachment.ToxicSpikes)
        battle.message "Poison spikes were scattered all around #{opponent.id}'s team's feet!"
      else
        @fail(battle)

extendMove 'Transform', ->
  @afterSuccessfulHit = (battle, user, target) ->
    if !user.attach(Attachment.Transform, {target})
      @fail(battle)
      return false
    battle.message "#{user.name} tranformed into #{target.name}!"

extendMove 'Trick Room', ->
  @execute = (battle, user, targets) ->
    if battle.attach(Attachment.TrickRoom)
      battle.message "#{user.name} twisted the dimensions!"
    else
      battle.message "The twisted dimensions returned to normal!"
      battle.unattach(Attachment.TrickRoom)

extendMove 'Trump Card', ->
  @basePower = (battle, user, target) ->
    switch user.pp(this)
      when 3
        50
      when 2
        60
      when 1
        80
      when 0
        200
      else
        40

extendMove 'U-turn', ->
  @afterSuccessfulHit = (battle, user, target) ->
    battle.forceSwitch(user)

extendMove 'Venoshock', ->
  @basePower = (battle, user, target) ->
    if target.has(Status.Toxic) || target.has(Status.Poison)
      2 * @power
    else
      @power

extendMove 'Volt Switch', ->
  @afterSuccessfulHit = (battle, user, target) ->
    battle.forceSwitch(user)

makeStatusCureAttackMove 'Wake-Up Slap', Status.Sleep

extendMove 'Weather Ball', ->
  @getType = (battle, user, target) ->
    if      battle.hasWeather(Weather.SUN)  then 'Fire'
    else if battle.hasWeather(Weather.RAIN) then 'Water'
    else if battle.hasWeather(Weather.HAIL) then 'Ice'
    else if battle.hasWeather(Weather.SAND) then 'Rock'
    else 'Normal'

  @basePower = (battle, user, target) ->
    if battle.hasWeather(Weather.NONE) then 50 else 100


extendMove 'Wish', ->
  @execute = (battle, user, targets) ->
    team = battle.getOwner(user).team
    @fail(battle)  unless team.attach(Attachment.Wish, {user})

extendMove 'Wring Out', ->
  @basePower = (battle, user, target) ->
    power = Math.floor(120 * user.currentHP / user.stat('hp'))
    Math.max(1, power)

extendMove 'Yawn', ->
  # TODO: Fail if safeguard is activate
  # NOTE: Insomnia and Vital Spirit guard against the sleep effect
  # but not yawn itself.
  @afterSuccessfulHit = (battle, user, target) ->
    if target.attach(Attachment.Yawn) && !target.hasStatus()
      battle.message "#{target.name} grew drowsy!"
    else
      @fail(battle)

# Keep this at the bottom or look up how it affects Metronome.
# TODO: Figure out a better solution
Moves['Confusion Recoil'] = new Move "Confusion recoil",
  "accuracy": 0,
  "damage": "physical",
  "power": 40,
  "priority": 0,
  "type": "???"

# Confusion never crits
extendMove 'Confusion Recoil', ->
  @isCriticalHit = -> false

Moves['Recharge'] = new Move("Recharge", target: "user")

# After everything to ensure that basePower is overridden last.
makeVulnerable = (moveName, byMove) ->
  extendMove byMove, ->
    oldBasePower = @basePower
    @basePower = (battle, user, target) ->
      power    = oldBasePower.call(this, battle, user, target)
      charging = target.get(Attachment.Charging)
      return power  if !charging?

      if charging.move == battle.getMove(moveName) then 2 * power else power

makeVulnerable('Fly', 'Gust')
makeVulnerable('Fly', 'Twister')
makeVulnerable('Bounce', 'Gust')
makeVulnerable('Bounce', 'Twister')
makeVulnerable('Dig', 'Earthquake')
makeVulnerable('Dig', 'Magnitude')
makeVulnerable('Dive', 'Surf')
makeVulnerable('Dive', 'Whirlpool')
