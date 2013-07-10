{Status, VolatileStatus} = require './status'
util = require './util'
{_} = require 'underscore'

class @Attachments
  constructor: ->
    @attachments = []

  push: (attachmentClass, options={}, attributes={}) =>
    throw new Error("Passed a non-existent Attachment.")  if !attachmentClass?
    attachment = @get(attachmentClass)
    if !attachment?
      attachment = new attachmentClass()
      for attribute, value of attributes
        attachment[attribute] = value
      @attachments.push(attachment)
      attachment.initialize(options)

    return null  if attachment.layers == attachment.maxLayers
    attachment.layers++
    return attachment

  # todo: should call Attachment#remove() somehow without causing infinite recursion
  unattach: (attachment) =>
    index = @indexOf(attachment)
    @attachments.splice(index, 1)  if index >= 0

  indexOf: (attachment) =>
    @attachments.map((a) -> a.constructor).indexOf(attachment)

  get: (attachment) =>
    @attachments[@indexOf(attachment)]

  contains: (attachment) =>
    @indexOf(attachment) != -1

  queryUntil: (funcName, conditional, args...) =>
    for attachment in _.clone(@attachments)
      result = attachment[funcName](args...)  if funcName of attachment
      break  if conditional(result)
    result

  query: (funcName, args...) =>
    @queryUntil(funcName, (-> false), args...)

  queryUntilTrue: (funcName, args...) =>
    conditional = (result) -> result == true
    @queryUntil(funcName, conditional, args...)

  queryUntilFalse: (funcName, args...) =>
    conditional = (result) -> result == false
    @queryUntil(funcName, conditional, args...)

  queryUntilNotNull: (funcName, args...) =>
    conditional = (result) -> result?
    @queryUntil(funcName, conditional, args...)

  queryChain: (funcName, result, args...) =>
    for attachment in _.clone(@attachments)
      result = attachment[funcName](result, args...)  if funcName of attachment
    result

# Attachments represents a pokemon's state. Some examples are
# status effects, entry hazards, and fire spin's trapping effect.
# Attachments are "attached" with Pokemon.attach(), and after
# that the attachment can be retrieved with Attachment.pokemon
class @Attachment
  name: "Attachment"

  maxLayers: 1

  constructor: ->
    @layers = 0

  initialize: =>

  remove: =>
    # Error if @pokemon is undefined
    @pokemon.unattach(@constructor)

  calculateWeight: (weight) => weight
  editAccuracy: (accuracy) => accuracy
  editEvasion: (evasion) => evasion
  afterBeingHit: (battle, move, user, target, damage) =>
  afterSuccessfulHit: (battle, move, user, target, damage) =>
  beforeMove: (battle, move, user, targets) =>
  isImmune: (battle, type) =>
  switchOut: (battle) =>
  switchIn: (battle, pokemon) =>
  beginTurn: (battle) =>
  endTurn: (battle) =>
  update: (battle, owner) =>
  # editBoosts: (stages) =>
  # editDamage: (damage, battle, move, user) =>
  # afterFaint: (battle) =>
  # shouldBlockExecution: (battle, move, user) =>

  # Pokemon-specific attachments
  # TODO: Turn Attachment into abstract class
  # TODO: Move into own PokemonAttachment
  modifyHp: (stat) => stat
  modifySpeed: (stat) => stat
  modifyAttack: (stat) => stat
  modifySpecialAttack: (stat) => stat
  modifyDefense: (stat) => stat
  modifySpecialDefense: (stat) => stat

Attachment = @Attachment

# Used for effects like Tailwind or Reflect.
class @TeamAttachment extends @Attachment
  name: "TeamAttachment"

  remove: =>
    @team.unattach(@constructor)

# Used for effects like Trick Room or Magic Room.
class @BattleAttachment extends @Attachment
  name: "BattleAttachment"

  remove: =>
    @battle.unattach(@constructor)

class @Attachment.Paralyze extends @Attachment
  name: "#{Status.PARALYZE}Attachment"

  beforeMove: (battle, move, user, targets) =>
    if battle.rng.next('paralyze chance') < .25
      battle.message "#{@pokemon.name} is fully paralyzed!"
      return false

  modifySpeed: (stat) =>
    Math.floor(stat / 4)

class @Attachment.Freeze extends @Attachment
  name: "#{Status.FREEZE}Attachment"

  beforeMove: (battle, move, user, targets) =>
    if move.thawsUser || battle.rng.next('unfreeze chance') < .2
      battle.message "#{@pokemon.name} thawed out!"
      @pokemon.cureStatus()
    else
      battle.message "#{@pokemon.name} is frozen solid!"
      return false

  afterBeingHit: (battle, move, user, target, damage) =>
    if !move.isNonDamaging() && move.type == 'Fire'
      battle.message "#{@pokemon.name} thawed out!"
      @pokemon.cureStatus()

class @Attachment.Poison extends @Attachment
  name: "#{Status.POISON}Attachment"

  endTurn: (battle) =>
    battle.message "#{@pokemon.name} was hurt by poison!"
    @pokemon.damage(@pokemon.stat('hp') >> 3)

class @Attachment.Toxic extends @Attachment
  name: "#{Status.TOXIC}Attachment"

  initialize: =>
    @counter = 0

  switchOut: =>
    @counter = 0

  endTurn: (battle) =>
    battle.message "#{@pokemon.name} was hurt by poison!"
    @counter = Math.min(@counter + 1, 15)
    @pokemon.damage Math.floor(@pokemon.stat('hp') * @counter / 16)

class @Attachment.Sleep extends @Attachment
  name: "#{Status.SLEEP}Attachment"

  initialize: =>
    @counter = 0

  switchOut: =>
    @counter = 0

  beforeMove: (battle, move, user, targets) =>
    @turns ||= battle.rng.randInt(1, 3, "sleep turns")
    if @counter == @turns
      battle.message "#{@pokemon.name} woke up!"
      @pokemon.cureStatus()
    else
      battle.message "#{@pokemon.name} is fast asleep."
      @counter += 1
      return false

class @Attachment.Burn extends @Attachment
  name: "#{Status.BURN}Attachment"

  endTurn: (battle) =>
    battle.message "#{@pokemon.name} was hurt by its burn!"
    @pokemon.damage(@pokemon.stat('hp') >> 3)

# An attachment that removes itself when a pokemon
# deactivates.
class @VolatileAttachment extends @Attachment
  switchOut: =>
    @remove()

class @Attachment.Flinch extends @VolatileAttachment
  name: VolatileStatus.FLINCH

  beforeMove: (battle, move, user, targets) =>
    battle.message "#{@pokemon.name} flinched!"
    false

  endTurn: =>
    @remove()

class @Attachment.Confusion extends @VolatileAttachment
  name: VolatileStatus.CONFUSION

  initialize: (attributes) ->
    @turns = attributes.battle.rng.randInt(1, 4, "confusion turns")
    @turn = 0

  beforeMove: (battle, move, user, targets) =>
    battle.message "#{@pokemon.name} is confused!"
    @turn++
    if @turn > @turns
      battle.message "#{@pokemon.name} snapped out of confusion!"
      @remove()
    else if battle.rng.next('confusion') < 0.5
      battle.message "#{@pokemon.name} hurt itself in confusion!"
      damage = battle.confusionMove.calculateDamage(battle, user, user)
      user.damage(damage)
      return false

class @Attachment.Disable extends @VolatileAttachment
  name: "DisableAttachment"

  initialize: (attributes) ->
    @blockedMove = attributes.move
    @turns = 4

  beginTurn: =>
    @pokemon.blockMove(@blockedMove)

  beforeMove: (battle, move, user, target) ->
    if move == @blockedMove
      battle.message "#{@pokemon.name}'s #{move.name} is disabled!"
      return false

  endTurn: (battle) =>
    @turns--
    if @turns == 0
      battle.message "#{@pokemon.name} is no longer disabled!"
      @remove()

class @Attachment.Yawn extends @VolatileAttachment
  name: 'YawnAttachment'

  initialize: =>
    @turn = 0

  endTurn: =>
    @turn += 1
    if @turn == 2
      @pokemon.setStatus(Status.SLEEP)
      @remove()

# TODO: Does weight get lowered if speed does not change?
class @Attachment.Autotomize extends @VolatileAttachment
  name: "AutotomizeAttachment"

  maxLayers: -1

  calculateWeight: (weight) =>
    Math.max(weight - 100 * @layers, .1)

class @Attachment.Nightmare extends @VolatileAttachment
  name: "NightmareAttachment"

  endTurn: (battle) =>
    if @pokemon.hasStatus(Status.SLEEP)
      battle.message "#{@pokemon.name} is locked in a nightmare!"
      @pokemon.damage Math.floor(@pokemon.stat('hp') / 4)
    else
      @remove()

class @Attachment.Taunt extends @VolatileAttachment
  name: "TauntAttachment"

  initialize: (attributes) =>
    {@battle} = attributes
    @turns = 3
    @turn = 0

  beginTurn: (battle) =>
    for move in @pokemon.moves
      if move.power == 0
        @pokemon.blockMove(move)

  beforeMove: (battle, move, user, targets) =>
    # TODO: user is always == pokemon. Will this change?
    if user == @pokemon && move.power == 0
      battle.message "#{@pokemon.name} can't use #{move.name} after the taunt!"
      return false

  endTurn: (battle) =>
    @turn++
    if @turn >= @turns
      battle.message "#{@pokemon.name}'s taunt wore off!"
      @remove()

  remove: =>
    delete @battle
    super()

class @Attachment.Wish extends @TeamAttachment
  name: "WishAttachment"

  initialize: (attributes) ->
    {user} = attributes
    @amount = Math.round(user.stat('hp') / 2)
    @wisherName = user.name
    @slot = @team.indexOf(user)
    @turns = 2
    @turn = 0

  endTurn: (battle) =>
    @turn++
    if @turn >= @turns
      pokemon = @team.at(@slot)
      if !pokemon.isFainted()
        battle.message "#{@wisherName}'s wish came true!"
        pokemon.damage(-@amount)
      @remove()

  remove: =>
    super()

class @Attachment.PerishSong extends @VolatileAttachment
  name: "PerishSongAttachment"

  initialize: =>
    @turns = 4
    @turn = 0

  endTurn: (battle) =>
    @turn++
    battle.message "#{@pokemon.name}'s perish count fell to #{@turns - @turn}!"
    if @turn >= @turns
      @pokemon.faint()
      @remove()

class @Attachment.Roost extends @VolatileAttachment
  name: "RoostAttachment"

  initialize: =>
    @oldTypes = @pokemon.types
    @pokemon.types = (type for type in @pokemon.types when type != 'Flying')
    if @pokemon.types.length == 0 then @pokemon.types = [ 'Normal' ]

  endTurn: (battle) =>
    @pokemon.types = @oldTypes
    @remove()

class @Attachment.Encore extends @VolatileAttachment
  name: "EncoreAttachment"

  initialize: =>
    @turns = 3
    @turn = 0
    @move = @pokemon.lastMove

  beginTurn: (battle) =>
    @pokemon.lockMove(@move)

  endTurn: (battle) =>
    @turn++
    if @turn >= @turns || @pokemon.pp(@move) == 0
      battle.message("#{@pokemon.name}'s Encore ended!")
      @remove()

class @Attachment.Torment extends @VolatileAttachment
  name: "TormentAttachment"

  beginTurn: (battle) =>
    @pokemon.blockMove(@pokemon.lastMove)  if @pokemon.lastMove?

class @Attachment.ChoiceLock extends @VolatileAttachment
  name: "ChoiceLockAttachment"

  initialize: =>
    @move = null

  beforeMove: (battle, move, user, targets) =>
    @move = move
    true

  beginTurn: (battle) =>
    @pokemon.lockMove(@move)  if @move?

  remove: =>
    delete @move
    super()

class @Attachment.IronBall extends @VolatileAttachment
  name: "IronBallAttachment"

  isImmune: (battle, type) =>
    return false  if type == 'Ground'

class @Attachment.AirBalloon extends @VolatileAttachment
  name: "AirBalloonAttachment"

  afterBeingHit: (battle, move, user, target, damage) =>
    return  if move.isNonDamaging()
    battle.message "#{target.name}'s #{target.getItem().name} popped!"
    target.removeItem()

  isImmune: (battle, type) =>
    return true  if type == 'Ground'

class @Attachment.Spikes extends @TeamAttachment
  name: "SpikesAttachment"

  maxLayers: 3

  switchIn: (battle, pokemon) =>
    return  if pokemon.isImmune(battle, "Ground")
    fraction = (10 - 2 * @layers)
    hp = pokemon.stat('hp')
    pokemon.damage Math.floor(hp / fraction)

class @Attachment.StealthRock extends @TeamAttachment
  name: "StealthRockAttachment"

  switchIn: (battle, pokemon) =>
    multiplier = util.typeEffectiveness("Rock", pokemon.types)
    hp = pokemon.stat('hp')
    pokemon.damage Math.floor(hp * multiplier / 8)

class @Attachment.ToxicSpikes extends @TeamAttachment
  name: "ToxicSpikesAttachment"

  maxLayers: 2

  switchIn: (battle, pokemon) =>
    if pokemon.hasType("Poison") && !pokemon.isImmune(battle, "Ground")
      name = battle.getOwner(pokemon).username
      battle.message "The poison spikes disappeared from around #{name}'s team's feet!"
      @remove()

    return  if pokemon.isImmune(battle, "Poison")

    if @layers == 1
      pokemon.setStatus(Status.POISON)
    else
      pokemon.setStatus(Status.TOXIC)

# A trap created by Fire Spin, Magma Storm, Bind, Clamp, etc
class @Attachment.Trap extends @VolatileAttachment
  name: "TrapAttachment"

  initialize: (attributes) =>
    {@moveName, @user, @turns} = attributes

  beginTurn: (battle) =>
    @pokemon.blockSwitch()

  endTurn: (battle) =>
    # For the first numTurns turns it will damage, and at numTurns + 1 it will wear off.
    # Therefore, if @turns = 5, this attachment should actually last for 6 turns.
    if @turns == 0
      battle.message "#{@pokemon.name} was freed from #{@moveName}!"
      @remove()
    else
      battle.message "#{@pokemon.name} is hurt by #{@moveName}!"
      @pokemon.damage Math.floor(@pokemon.stat('hp') / @getDamagePerTurn())
      @turns -= 1

  getDamagePerTurn: =>
    if @user.hasItem("Binding Band")
      8
    else
      16

  remove: =>
    @user.unattach(Attachment.TrapLeash)
    delete @user
    super()

# If the creator if fire spin switches out, the trap will end
# TODO: What happens if another ability removes the trap, and then firespin is used again?
class @Attachment.TrapLeash extends @VolatileAttachment
  name: "TrapLeashAttachment"

  initialize: (attributes) =>
    {@target} = attributes

  remove: =>
    @target.unattach(Attachment.Trap)
    delete @target
    super()

# Has a 50% chance to immobilize a Pokemon before it moves.
class @Attachment.Attract extends @VolatileAttachment
  name: "AttractAttachment"

  initialize: (attributes) =>
    {source} = attributes
    if @pokemon.hasItem("Destiny Knot") && !source.has(Attachment.Attract)
      source.attach(Attachment.Attract, {source})
      @pokemon.removeItem()

  beforeMove: (battle, move, user, targets) =>
    if battle.rng.next('attract chance') < .5
      battle.message "#{@pokemon.name} is immobilized by love!"
      return false

class @Attachment.FocusEnergy extends @VolatileAttachment
  name: "FocusEnergyAttachment"

class @Attachment.MicleBerry extends @VolatileAttachment
  name: "MicleBerryAttachment"

  initialize: =>
    @turns = 1

  editAccuracy: (accuracy) =>
    Math.floor(accuracy * 1.2)

  endTurn: (battle) =>
    if @turns == 0
      @remove()
    else
      @turns--

class @Attachment.EvasionItem extends @VolatileAttachment
  name: "EvasionItemAttachment"

  initialize: (attributes) =>
    @ratio = attributes.ratio || 0.9

  editEvasion: (accuracy) =>
    Math.floor(accuracy * @ratio)

class @Attachment.Metronome extends @VolatileAttachment
  name: "MetronomeAttachment"

  maxLayers: 5

  initialize: (attributes) ->
    {@move} = attributes

  beforeMove: (battle, move) ->
    @remove()  if move != @move

class @Attachment.Screen extends @TeamAttachment
  name: "ScreenAttachment"

  initialize: (attributes) =>
    {user} = attributes
    @turns = (if user?.hasItem("Light Clay") then 8 else 5)

  endTurn: (battle) =>
    @turns--
    if @turns == 0
      @remove()

class @Attachment.Reflect extends @Attachment.Screen
  name: "ReflectAttachment"

class @Attachment.LightScreen extends @Attachment.Screen
  name: "LightScreenAttachment"

class @Attachment.Identify extends @VolatileAttachment
  name: "IdentifyAttachment"

  initialize: (attributes) =>
    {@type} = attributes

  editBoosts: (stages) =>
    stages.evasion = 0
    stages

  isImmune: (battle, type) =>
    return false  if type == @type

class @Attachment.DefenseCurl extends @VolatileAttachment
  name: "DefenseCurl"

class @Attachment.FocusPunch extends @VolatileAttachment
  name: "FocusPunchAttachment"

  beforeMove: (battle, move, user, targets) =>
    hit = user.lastHitBy
    if hit? && !hit.move.isNonDamaging() && hit.turn == battle.turn
      battle.message "#{user.name} lost its focus and couldn't move!"
      return false

class @Attachment.MagnetRise extends @VolatileAttachment
  name: "MagnetRiseAttachment"

  initialize: =>
    @turns = 5

  isImmune: (battle, type) =>
    return true  if type == "Ground"

  endTurn: (battle) =>
    @turns -= 1
    @remove()  if @turns == 0

class @Attachment.LockOn extends @VolatileAttachment
  name: "LockOnAttachment"

  initialize: =>
    @turns = 2

  editAccuracy: (stat) =>
    0  # Always hits

  endTurn: (battle) =>
    @turns -= 1
    @remove()  if @turns == 0

class @Attachment.Minimize extends @VolatileAttachment
  name: "MinimizeAttachment"

class @Attachment.MeanLook extends @VolatileAttachment
  name: "MeanLookAttachment"

  beginTurn: (battle) =>
    @pokemon.blockSwitch()

class @Attachment.Recharge extends @VolatileAttachment
  name: "RechargeAttachment"

  initialize: =>
    @turns = 2

  beginTurn: (battle) =>
    @pokemon.blockSwitch()
    @pokemon.blockMoves()
    {id} = battle.getOwner(@pokemon)
    battle.recordMove(id, battle.getMove("Recharge"))

  beforeMove: (battle, move, user, targets) =>
    battle.message "#{user.name} must recharge!"
    return false

  endTurn: (battle) =>
    @turns -= 1
    @remove()  if @turns == 0

class @Attachment.Momentum extends @VolatileAttachment
  name: "MomentumAttachment"

  maxLayers: 5

  initialize: (attributes) =>
    {@move} = attributes
    @turns = 1

  beginTurn: (battle) =>
    @pokemon.blockSwitch()
    @pokemon.lockMove(@move)

  endTurn: (battle) =>
    @turns -= 1
    @remove()  if @turns == 0 || @layers == @maxLayers

class @Attachment.MeFirst extends @VolatileAttachment
  name: "MeFirstAttachment"

  endTurn: (battle) =>
    @remove()

class @Attachment.Charge extends @VolatileAttachment
  name: "ChargeAttachment"

  initialize: =>
    @turns = 2

  endTurn: (battle) =>
    @turns -= 1
    @remove()  if @turns == 0

class @Attachment.LeechSeed extends @VolatileAttachment
  name: "LeechSeedAttachment"

  initialize: (attributes) =>
    {@user, @target} = attributes

  endTurn: (battle) =>
    hp = @target.stat('hp')
    damage = Math.min(Math.floor(hp / 8), @target.currentHP)
    @target.damage(damage)
    @user.drain(damage)
    battle.message "#{@target.name}'s health is sapped by Leech Seed!"

class @Attachment.ProtectCounter extends @VolatileAttachment
  name: "ProtectCounterAttachment"

  maxLayers: -1

  successChance: =>
    x = Math.pow(2, @layers - 1)
    if x >= 256 then Math.pow(2, 32) else x

  endTurn: =>
    @turns--
    @remove()  if @turns == 0

class @Attachment.Protect extends @VolatileAttachment
  name: "ProtectAttachment"

  shouldBlockExecution: (battle, move, user) =>
    if move.hasFlag("protect")
      battle.message "#{@pokemon.name} protected itself!"
      return true

  endTurn: =>
    @remove()

class @Attachment.Endure extends @VolatileAttachment
  name: "EndureAttachment"

  endTurn: =>
    @remove()

  editDamage: (damage, battle, move, user) =>
    Math.min(damage, user.currentHP - 1)

class @Attachment.Curse extends @VolatileAttachment
  name: "CurseAttachment"

  endTurn: (battle) =>
    @pokemon.damage Math.floor(@pokemon.stat('hp') / 4)
    battle.message "#{@pokemon.name} was afflicted by the curse!"

class @Attachment.DestinyBond extends @VolatileAttachment
  name: "DestinyBondAttachment"

  afterFaint: (battle) =>
    pokemon = battle.lastPokemon
    if pokemon? && pokemon.isAlive()
      pokemon.faint()
      battle.message "#{pokemon.name} took its attacker down with it!"

  beforeMove: (battle, move, user, targets) =>
    @remove()

class @Attachment.Grudge extends @VolatileAttachment
  name: "GrudgeAttachment"

  afterFaint: (battle) =>
    pokemon = battle.lastPokemon
    if pokemon? && pokemon.isAlive()
      move = pokemon.lastMove
      pokemon.setPP(move, 0)
      battle.message "#{pokemon.name}'s #{move.name} lost all its PP due to the grudge!"

  beforeMove: (battle, move, user, targets) =>
    @remove()

class @Attachment.Pursuit extends @VolatileAttachment
  name: "PursuitAttachment"

  informSwitch: (battle, switcher) =>
    move = battle.getMove('Pursuit')
    battle.cancelAction(@pokemon)
    @pokemon.attach(Attachment.PursuitModifiers)
    move.execute(battle, @pokemon, [ switcher ])
    @pokemon.unattach(Attachment.PursuitModifiers)
    @remove()

  endTurn: =>
    @remove()

class @Attachment.PursuitModifiers extends @VolatileAttachment
  name: "PursuitModifiersAttachment"

  editAccuracy: (accuracy) =>
    0

class @Attachment.Substitute extends @VolatileAttachment
  name: "SubstituteAttachment"

  initialize: (attributes) =>
    {@battle, @hp} = attributes

  transformHealthChange: (damage) =>
    @hp -= damage
    if @hp <= 0
      @battle.message "#{@pokemon.name}'s substitute faded!"
      @remove()
    else
      @battle.message "The substitute took damage for #{@pokemon.name}!"
    return 0

  shouldBlockExecution: (battle, move, user) =>
    if move.isNonDamaging() && !move.hasFlag('authentic')
      move.fail(battle)
      return true

class @Attachment.Stockpile extends @VolatileAttachment
  name: "StockpileAttachment"

  maxLayers: 3

class @Attachment.Rage extends @VolatileAttachment
  name: "RageAttachment"

  beforeMove: (battle, move, user, targets) =>
    @remove()

  afterBeingHit: (battle, move, user, target, damage) =>
    return  if move.isNonDamaging()
    target.boost(attack: 1)
    battle.message "#{target.name}'s rage is building!"

class @Attachment.ChipAway extends @VolatileAttachment
  name: "ChipAwayAttachment"

  editBoosts: (stages) =>
    stages.evasion = 0
    stages.defense = 0
    stages.specialDefense = 0
    stages

class @Attachment.AquaRing extends @VolatileAttachment
  name: "AquaRingAttachment"

  endTurn: (battle) =>
    amount = Math.floor(@pokemon.stat('hp') / 16)
    # Aqua Ring is considered a drain move for the purposes of Big Root.
    @pokemon.drain(amount)
    battle.message "Aqua Ring restored #{@pokemon.name}'s HP!"

class @Attachment.Ingrain extends @VolatileAttachment
  name: "IngrainAttachment"

  endTurn: (battle) =>
    amount = Math.floor(@pokemon.stat('hp') / 16)
    # Ingrain is considered a drain move for the purposes of Big Root.
    @pokemon.drain(amount)
    battle.message "#{@pokemon.name} absorbed nutrients with its roots!"

  beginTurn: (battle) =>
    @pokemon.blockSwitch()

  informPhase: (battle, phaser) ->
    battle.message "#{@pokemon.name} anchored itself with its roots!"
    return false

  shouldBlockExecution: (battle, move, user) =>
    if move == battle.getMove("Telekinesis")
      move.fail(battle)
      return true

  isImmune: (battle, type) =>
    return false  if type == 'Ground'

class @Attachment.Embargo extends @VolatileAttachment
  name: "EmbargoAttachment"

  initialize: =>
    @turns = 5
    @pokemon.blockItem()

  beginTurn: (battle) =>
    @pokemon.blockItem()

  endTurn: (battle) =>
    @turns--
    if @turns == 0
      battle.message "#{@pokemon.name} can use items again!"
      @remove()

class @Attachment.Charging extends @VolatileAttachment
  name: "ChargingAttachment"

  initialize: (attributes) =>
    {@message, @vulnerable, @move, @condition} = attributes
    @charging = false

  beforeMove: (battle, move, user, targets) =>
    if user.hasItem("Power Herb")
      battle.message "#{user.name} became fully charged due to its Power Herb!"
      @charging = true
      user.removeItem()

    if @charging || @condition?(battle, move, user, targets)
      @remove()
      return

    @charging = true
    battle.message @message.replace(/$1/g, user.name)
    return false

  beginTurn: (battle) =>
    # TODO: Add targets
    {id} = battle.getOwner(@pokemon)
    battle.recordMove(id, @move)

  shouldBlockExecution: (battle, move, user) =>
    if @charging && (move not in @vulnerable.map((v) -> battle.getMove(v)))
      battle.message "#{@pokemon.name} avoided the attack!"
      return true

  remove: =>
    super()
    delete @move
    delete @message
    delete @vulnerable

class @Attachment.FuryCutter extends @VolatileAttachment
  name: "FuryCutterAttachment"

  maxLayers: 3

  initialize: (attributes) =>
    {@move} = attributes

  beforeMove: (battle, move, user, targets) =>
    @remove()  if move != @move

class @Attachment.Imprison extends @VolatileAttachment
  name: "ImprisonAttachment"

  initialize: (attributes) =>
    {@moves, battle} = attributes
    for pokemon in battle.getOpponents(@pokemon)
      pokemon.attach(Attachment.ImprisonPrevention, {@moves})

  beginTurn: (battle) =>
    for pokemon in battle.getOpponents(@pokemon)
      pokemon.attach(Attachment.ImprisonPrevention, {@moves})

  switchOut: (battle) =>
    for pokemon in battle.getOpponents(@pokemon)
      pokemon.unattach(Attachment.ImprisonPrevention)
    super(battle)

class @Attachment.ImprisonPrevention extends @VolatileAttachment
  name: "ImprisonPreventionAttachment"

  initialize: (attributes) =>
    {@moves} = attributes

  beginTurn: (battle) =>
    @pokemon.blockMove(move)  for move in @moves

  beforeMove: (battle, move, user, targets) =>
    if move in @moves
      battle.message "#{user.name} can't use the sealed #{move.name}!"
      return false

class @Attachment.Present extends @VolatileAttachment
  name: "PresentAttachment"

  initialize: (attributes) =>
    {@power} = attributes

  endTurn: =>
    @remove()

# Lucky Chant's CH prevention is inside Move#isCriticalHit.
class @Attachment.LuckyChant extends @TeamAttachment
  name: "LuckyChantAttachment"

  initialize: =>
    @turns = 5

  endTurn: (battle) =>
    @turns--
    if @turns == 0
      # TODO: Less hacky way of getting username
      {username} = (p for id, p of battle.players when p.team == @team)[0]
      battle.message "#{username}'s team's Lucky Chant wore off!"
      @remove()

class @Attachment.LunarDance extends @TeamAttachment
  name: "LunarDanceAttachment"

  switchIn: (battle, pokemon) =>
    battle.message "#{pokemon.name} became cloaked in mystical moonlight!"
    pokemon.currentHP = pokemon.stat('hp')
    pokemon.cureStatus()
    pokemon.resetAllPP()

class @Attachment.HealingWish extends @TeamAttachment
  name: "HealingWishAttachment"

  switchIn: (battle, pokemon) =>
    battle.message "The healing wish came true for #{pokemon.name}!"
    pokemon.currentHP = pokemon.stat('hp')
    pokemon.cureStatus()

class @Attachment.MagicCoat extends @VolatileAttachment
  name: "MagicCoatAttachment"

  initialize: =>
    @bounced = false

  shouldBlockExecution: (battle, move, user) =>
    return  unless move.hasFlag("reflectable")
    return  if user.getAttachment(Attachment.MagicCoat)?.bounced
    return  if @bounced
    @bounced = true
    battle.message "#{@pokemon.name} bounced the #{move.name} back!"
    move.execute(battle, @pokemon, [ user ])
    return true

  endTurn: (battle) =>
    @remove()

class @Attachment.Telekinesis extends @VolatileAttachment
  name: "TelekinesisAttachment"

  initialize: =>
    @turns = 3

  editEvasion: =>
    0  # Always hit

  isImmune: (battle, type) =>
    return true  if type == 'Ground'

  endTurn: (battle) =>
    @turns--
    if @turns == 0
      battle.message "#{@pokemon} was freed from the telekinesis!"
      @remove()

class @Attachment.SmackDown extends @VolatileAttachment
  name: "SmackDownAttachment"

  isImmune: (battle, type) =>
    return false  if type == 'Ground'

  shouldBlockExecution: (battle, move, user) =>
    if move in [ battle.getMove("Telekinesis"), battle.getMove("Magnet Rise") ]
      move.fail(battle)
      return true

class @Attachment.EchoedVoice extends @BattleAttachment
  name: "EchoedVoiceAttachment"

  maxLayers: 4

  initialize: =>
    @turns = 2

  endTurn: =>
    @turns--
    @remove()  if @turns == 0

class @Attachment.Rampage extends @VolatileAttachment
  name: "RampageAttachment"

  maxLayers: -1

  initialize: (attributes) =>
    {battle, @move} = attributes
    @turns = battle.rng.randInt(2, 3, "rampage turns")
    @turn = 0

  beginTurn: (battle) =>
    @pokemon.blockSwitch()
    @pokemon.lockMove(@move)

  endTurn: (battle) =>
    @turn++
    if @turn >= @turns
      battle.message "#{@pokemon.name} became confused due to fatigue!"
      @pokemon.attach(Attachment.Confusion, {battle})
      @remove()
    else
      # afterSuccessfulHit increases the number of layers. If the number of
      # layers is not keeping up with the number of turns passed, then the
      # Pokemon's move was interrupted and we should stop rampaging.
      @remove()  if @turn > @layers

# The way Trick Room reverses turn order is implemented in Battle#sortActions.
class @Attachment.TrickRoom extends @BattleAttachment
  name: "TrickRoomAttachment"

  initialize: =>
    @turns = 5

  endTurn: (battle) =>
    @turns--
    if @turns == 0
      battle.message "The twisted dimensions returned to normal!"
      @remove()

class @Attachment.Transform extends @VolatileAttachment
  name: "TransformAttachment"

  initialize: (attributes) =>
    {target} = attributes
    # Save old data
    {@ability, @species, @moves, @stages, @types, @gender, @weight} = @pokemon
    {@ppHash, @maxPPHash} = @pokemon
    # This data is safe to be copied.
    @pokemon.ability = target.ability
    @pokemon.species = target.species
    @pokemon.gender  = target.gender
    @pokemon.weight  = target.weight
    # The rest aren't.
    @pokemon.moves   = _.clone(target.moves)
    @pokemon.stages  = _.clone(target.stages)
    @pokemon.types   = _.clone(target.types)
    @pokemon.resetAllPP(5)

  remove: =>
    # Restore old data
    @pokemon.ability   = @ability
    @pokemon.species   = @species
    @pokemon.moves     = @moves
    @pokemon.stages    = @stages
    @pokemon.types     = @types
    @pokemon.gender    = @gender
    @pokemon.weight    = @weight
    @pokemon.ppHash    = @ppHash
    @pokemon.maxPPHash = @maxPPHash
    super()

class @Attachment.Fling extends @VolatileAttachment
  name: "FlingAttachment"

  initialize: =>
    @item = null

  beforeMove: (battle, move, user, targets) =>
    # The move may be changed by something like Encore
    return  if move != battle.getMove("Fling")
    if user.hasItem() && user.hasTakeableItem() && !user.isItemBlocked()
      @item = user.getItem()
      user.removeItem()

  endTurn: =>
    @remove()

class @Attachment.BeatUp extends @VolatileAttachment
  name: "BeatUpAttachment"

  initialize: =>
    @index = -1

  shouldBlockExecution: (battle, move, user) =>
    {team} = battle.getOwner(user)
    @index += 1
    pokemon = team.at(@index)
    pokemon.hasStatus() || pokemon.isFainted()
