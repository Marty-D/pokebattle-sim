module.exports = (grunt) ->
  grunt.initConfig
    pkg: grunt.file.readJSON('package.json')
    concurrent:
      compile: ["jade", "stylus", "coffee", "concat"]
      server:
        tasks: ["nodemon", "watch"]
        options:
          logConcurrentOutput: true
    jade:
      compile:
        options:
          client: true
          compileDebug: false
          processName: (fileName) ->
            index = fileName.lastIndexOf('/')
            fileName = fileName.substr(index + 1)
            fileName.substr(0, fileName.indexOf('.'))
        files:
          "public/js/templates.js": "client/views/*.jade"
    stylus:
      compile:
        use: [ require('nib') ]
        files:
          "public/css/main.css": "client/app/css/main.styl"
    coffee:
      compile:
        files:
          'public/js/app.js': [
            "client/app/js/models/**/*.coffee"
            "client/app/js/collections/**/*.coffee"
            "client/app/js/views/**/*.coffee"
            "client/app/js/concerns/**/*.coffee"
            "client/app/js/**/*.coffee"
            "shared/**/*.coffee"
          ]
    concat:
      dist:
        dest: 'public/js/vendor.js'
        src: [
          "client/vendor/js/jquery.js"
          "client/vendor/js/underscore.js"
          "client/vendor/js/*.js"
        ]
    watch:
      # Note: These actually take subdirectories into account.
      templates:
        files: ['client/views/*.jade']
        tasks: 'jade'
      css:
        files: ['client/*.styl']
        tasks: 'stylus'
      js:
        files: ['client/app/*.coffee', 'shared/*.coffee']
        tasks: 'coffee'
      vendor:
        files: ['client/vendor/*.js']
        tasks: 'concat'
    nodemon:
      development:
        options:
          file: "start.js"
          ignoredFiles: [
            '.DS_Store'
            '.git/'
            'pokebattle-db'
            'test/'
            'scrapers/*'
            'client/*'
            'public/*'
            'Gruntfile*'
            'package.json'
            '*.md'
            '*.txt'
          ]

  grunt.loadNpmTasks('grunt-contrib-jade')
  grunt.loadNpmTasks('grunt-contrib-stylus')
  grunt.loadNpmTasks('grunt-contrib-coffee')
  grunt.loadNpmTasks('grunt-contrib-concat')
  grunt.loadNpmTasks('grunt-contrib-watch')
  grunt.loadNpmTasks('grunt-nodemon')
  grunt.loadNpmTasks('grunt-concurrent')
  grunt.registerTask('heroku:production', 'concurrent:compile')
  grunt.registerTask('default', ['concurrent:compile', 'concurrent:server'])
