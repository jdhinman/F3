module(...,package.seeall)

QuestManager.NewJobInstanceThread("JobBlacksmithInstance")

function JobBlacksmithInstance:Init()
	Layers.ActivateLayer(self.JobData.Layer)
end

function JobBlacksmithInstance:Update()
	while true do
		coroutine.yield()
		ScriptFunction.JobReactToOptionalQuestSuspension(self.JobData.Layer)
	end
end
