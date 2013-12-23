should = require 'should'
{BattleQueue} = require('../server/queue')
db = require('../server/database')

describe 'BattleQueue', ->
  it 'should be empty by default', ->
    new BattleQueue().queue.should.be.empty

  describe '#add', ->
    it 'queues a new player', ->
      queue = new BattleQueue()
      queue.add(id: 'derp', {})
      queue.queue.should.have.length 1

    it 'queues two players', ->
      queue = new BattleQueue()
      queue.add(id: 'batman', {})
      queue.add(id: 'superman', {})
      queue.queue.should.have.length 2

    it 'cannot queue the same player twice', ->
      queue = new BattleQueue()
      queue.add(id: 'batman', {})
      queue.add(id: 'batman', {})
      queue.queue.should.have.length 1

    it 'cannot queue falsy references', ->
      queue = new BattleQueue()
      queue.add(null, {})
      queue.add(false, {})
      queue.add(undefined, {})
      queue.queue.should.have.length 0

  describe '#remove', ->
    it 'can dequeue old players', ->
      queue = new BattleQueue()
      player = {}
      queue.add(player, {})
      queue.remove(player)
      queue.queue.should.have.length 0

    it "can take an array of players", ->
      queue = new BattleQueue()
      player1 = {}
      player2 = {}
      queue.add(player1, {})
      queue.add(player2, {})
      queue.remove([ player1, player2 ])
      queue.queue.should.have.length 0

  describe '#queuedPlayers', ->
    it 'returns the players who are queued', ->
      queue = new BattleQueue()
      dude = {id: 'dude'}
      queue.add(dude)
      queue.queuedPlayers().should.includeEql dude
      queue.queuedPlayers().should.have.length 1

  describe '#pairPlayers', ->
    afterEach (done) ->
      db.flushdb(done)

    it 'takes players out of the queue', (done) ->
      queue = new BattleQueue()
      queue.add(id: 'batman')
      queue.add(id: 'superman')
      queue.pairPlayers ->
        queue.queuedPlayers().should.be.empty
        done()

    it 'leaves one person out if the queue length is odd', (done) ->
      queue = new BattleQueue()
      queue.add(id: 'batman')
      queue.add(id: 'superman')
      queue.add(id: 'flash')
      queue.pairPlayers ->
        queue.queuedPlayers().should.have.length 1
        done()

    it 'returns an array of pairs', (done) ->
      queue = new BattleQueue()
      queue.add(id: 'batman')
      queue.add(id: 'superman')
      queue.add(id: 'flash')
      queue.add(id: 'spiderman')
      queue.pairPlayers (err, results) ->
        should.not.exist(err)
        should.exist(results)
        results.should.be.instanceOf(Array)
        results.should.have.length(2)
        done()

    it "returns an array of pairs in the order of their rating", (done) ->
      db.mset("ratings:batman", 1, "ratings:superman", 4,
        "ratings:flash", 3, "ratings:spiderman", 2)
      queue = new BattleQueue()
      queue.add(id: 'batman')
      queue.add(id: 'superman')
      queue.add(id: 'flash')
      queue.add(id: 'spiderman')
      queue.pairPlayers (err, results) ->
        should.not.exist(err)
        should.exist(results)
        results.should.be.instanceOf(Array)
        results.should.have.length(2)
        results = results.map (result) ->
          result.map (p) -> p.player.id
        results.should.eql [[ "batman", "spiderman" ]
                            [ "flash", "superman"   ]]
        done()
