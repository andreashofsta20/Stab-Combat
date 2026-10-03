-- Readiness is signalled by completed server startup jobs, rather than a fixed
-- ten-second pause that could be too long or still too short.
return require(script.Parent.Parent.StartupService)
