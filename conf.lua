function love.conf(t)
    t.window.width = 1920
    t.window.height = 1080
    t.window.title = "Rhythm Game (Conf)" -- Title from conf
    t.modules.joystick = true
    t.modules.physics = false -- Disable physics if not used
end
