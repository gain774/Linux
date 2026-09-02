-- 禁止武器の所持をサーバーへ報告する。
-- クライアント側の申告なので万能ではないが、既製のチートメニューは
-- この報告を止めないため実用上は引っかかる。

local hashes = {}

CreateThread(function()
    for _, name in ipairs(ACConfig.BlacklistedWeapons) do
        hashes[#hashes + 1] = { name = name, hash = GetHashKey(name) }
    end

    while true do
        Wait(5000)

        local ped = PlayerPedId()
        if ped and ped ~= 0 and not IsEntityDead(ped) then
            for _, weapon in ipairs(hashes) do
                if HasPedGotWeapon(ped, weapon.hash, false) then
                    TriggerServerEvent('gain_anticheat:reportWeapon', weapon.name)
                    Wait(10000)
                    break
                end
            end
        end
    end
end)
