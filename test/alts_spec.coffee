require('./helpers')

should = require('should')
alts = require('../server/alts')

describe "Alts", ->
  describe '#isAltNameValid', ->
    it 'allows alphanumeric and - and _ characters', ->
      alts.isAltNameValid("im-DA_best 251").should.be.true

    it 'blocks invalid alt names', ->
      alts.isAltNameValid().should.be.false
      alts.isAltNameValid("").should.be.false
      alts.isAltNameValid("itsme:").should.be.false
      alts.isAltNameValid("Blue  Kirby").should.be.false
      alts.isAltNameValid(("a"  for x in [0...16]).join('')).should.be.false

  describe '#createAlt', ->
    it 'creates a new alt', (done) ->
      alts.createAlt "player1", "TEST", (err) ->
        should.not.exist(err)
        alts.listUserAlts "player1", (err, results) ->
          results.length.should.eql 1
          done()

    it 'fails if the alt name is already being used', (done) ->
      alts.createAlt "player1", "TEST", ->
        alts.createAlt "player1", "TEST", (err) ->
          should.exist(err)
          done()

    it 'fails if the user already has 5 alts', (done) ->
      alts.createAlt "player1", "TEST1", (err) ->
        should.not.exist(err)
        alts.createAlt "player1", "test2", (err) ->
          should.not.exist(err)
          alts.createAlt "player1", "test3", (err) ->
            should.not.exist(err)
            alts.createAlt "player1", "test4", (err) ->
              should.not.exist(err)
              alts.createAlt "player1", "test5", (err) ->
                should.not.exist(err)
                alts.createAlt "player1", "test6", (err) ->
                  should.exist(err)
                  done()

  describe '#listUserAlts', ->
    it 'returns the same number of alts that were created', (done) ->
      alts.createAlt "player1", "TEST1", (err) ->
        alts.createAlt "player1", "test2", (err) ->
          alts.listUserAlts "player1", (err, alts) ->
            ["TEST1", "test2"].should.eql(alts)
            done()

  describe '#isAltOwnedBy', ->
    it 'returns false if the user does not own the alt', (done) ->
      alts.isAltOwnedBy "player1", "test", (err, result) ->
        should.not.exist(err)
        result.should.be.false

        # make it so another user owns the alt. It should still be false
        alts.createAlt "anotherguy", "test", (err) ->
          should.not.exist(err)
          alts.isAltOwnedBy "player1", "test", (err, result) ->
            should.not.exist(err)
            result.should.be.false
            done()

    it 'returns true if the user owns the alt', (done) ->
      # make it so another user owns the alt. It should still be false
      alts.createAlt "player1", "test", (err) ->
        should.not.exist(err)
        alts.isAltOwnedBy "player1", "test", (err, result) ->
          should.not.exist(err)
          result.should.be.true
          done()

    it 'returns true on null alt name', (done) ->
      alts.isAltOwnedBy "player1", null, (err, result) ->
        result.should.be.true
        done()

  describe '#getIdOwner', ->
    it 'reverses #uniqueId', ->
      id = "atestId"
      uniqueId = alts.uniqueId(id, "altName")
      uniqueId.should.not.equal(id)
      alts.getIdOwner(uniqueId).should.equal(id)

    it 'returns the given id if the id does not belong to an alt', ->
      id = "atestId"
      alts.getIdOwner(id).should.equal(id)
