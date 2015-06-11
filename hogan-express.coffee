###!
 * Copyright (c) 2012 Andrew Volkov <hello@vol4ok.net>
###

extend = (dest, srcs...) ->
  for src in srcs
    for own k, v of src
      if isObj(v)
        dest[k] = extend({}, src[k])
      else
        dest[k] = v
  return dest # Don't leave implicit - returns result of comprehension

isObj = (obj) ->
  obj && obj.toString && obj.toString() == '[object Object]'

$ = {}
extend $, require 'fs'
extend $, require 'util'
extend $, require 'path'
hogan = require 'hogan.js'

cache = {}
ctx = {}

read = (path, options, fn) ->
  str = cache[path]
  return fn(null, str) if (options.cache and str)
  $.readFile path, 'utf8', (err, str) ->
    return fn(err) if (err)
    # Remove potential UTF Byte Order Mark
    str = str.replace(/^\uFEFF/, '')
    cache[path] = str if (options.cache)
    fn(null, str)

renderPartials = (partials, opt, fn) ->
  count = 1
  result = {}
  for name, path of partials
    continue unless typeof path is 'string'
    path += ctx.ext unless $.extname(path)
    path = ctx.lookup(path)
    count++
    read path, opt, ((name, path) ->
        return (err, str) ->
          return unless count
          if err
            count = 0
            fn(err)
          result[name] = str
          fn(null, result) unless --count
      )(name, path)
  fn(null, result) unless --count

renderLayout = (path, opt, fn) ->
  return fn(null, false) unless path
  path += ctx.ext unless $.extname(path)
  path = ctx.lookup(path)
  return fn(null, false) unless path
  read path, opt, (err, str) ->
    return fn(err) if (err)
    fn(null, str)

customContent = (str, tag, opt, partials) ->
  oTag = "{{##{tag}}}"
  cTag = "{{/#{tag}}}"
  text = str.substring(str.indexOf(oTag) + oTag.length, str.indexOf(cTag))
  hogan.compile(text, opt).render(opt, partials)

render = (path, opt, fn) ->
  ctx = this
  partials = opt.settings.partials or {}
  partials = extend(partials, opt.partials) if opt.partials

  lambdas = opt.settings.lambdas or {}
  lambdas = extend(lambdas, opt.lambdas) if opt.lambdas

  # create the lambdafied functions
  # this way of dealing with lambdas assumes you'll want
  # to call your function on the rendered content instead
  # of the original template string
  opt.lambdas = {}
  lambdaIndexes = {}
  for name, lambda of lambdas
    do (name, lambda) ->
      lambdaIndexes[name] = 0
      opt.lambdas[name] = ->
        lcontext = @
        return (text) ->
          if (! lcontext.lambdaVals?) then lcontext.lambdaVals = {}
          if (! lcontext.lambdaVals[name]?) then lcontext.lambdaVals[name] = {}

          # getting the context right here is important
          # it must account for "locals" and values in the current context
          #  ... particually interesting when applying within a list
          lctx= {}
          lctx = extend lctx, opt._locals if opt._locals
          lctx = extend lctx, lcontext
          
          lcontext.lambdaVals[name][lambdaIndexes[name]] = lambda(hogan.compile(text).render(lctx),lctx)
          rtmpl = "{{{ lambdaVals." + name + "." + lambdaIndexes[name] + " }}}"
          lambdaIndexes[name] = lambdaIndexes[name] + 1
          return rtmpl

  renderPartials partials, opt, (err, partials) ->
    return fn(err) if (err)
    layout = if opt.layout is undefined
      opt.settings.layout
    else
      layout = opt.layout
    renderLayout layout, opt, (err, layout) ->
      read path, opt, (err, str) ->
        return fn(err) if (err)
        try
          tmpl = hogan.compile(str, opt)
          result = tmpl.render(opt, partials)
          customTags = str.match(/({{#yield-\w+}})/g)
          yields = {}
          if customTags
            for customTag in customTags
              tag = customTag.match(/{{#([\w-]+)}}/)[1]
              if tag
                if layout
                  opt[tag] = customContent(str, tag, opt, partials)
                else
                  yields[tag.replace('yield-', '')] = customContent(str, tag, opt, partials)
          if layout
            opt.yield = result
            tmpl = hogan.compile(layout, opt)
            result = tmpl.render(opt, partials)
            return fn(null, result)
          return fn(null, result, yields)
        catch err
          fn(err)

module.exports = render
