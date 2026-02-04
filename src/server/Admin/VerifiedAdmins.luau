local VerifiedAdmins = {}

VerifiedAdmins.IDS = {
    3353659057, 9304217232, 1354368060
}


VerifiedAdmins.CheckAdmin = function(userId)
    for _, ID in pairs(VerifiedAdmins.IDS) do
        if ID == userId then
            return true
        end
    end
    return false
end



return VerifiedAdmins

