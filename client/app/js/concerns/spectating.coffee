$(document).on 'click', '.spectate', ->
  battleId = $(this).data('battle-id')
  PokeBattle.socket.send('spectate battle', battleId)
