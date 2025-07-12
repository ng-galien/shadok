pipeline {
    stage("Renommer le projet") {
        args: oldName: "shadock", newName: "shadok" {
            renmameDirectory(oldName, newName)
            renameArtifact(oldName, newName)
        }
    }
    stage("verify project") {
        tool("maven") {
            instruction("compiler le projet avec Maven")
        }
        result {
            onSuccess {
                tool("git") {
                    instruction("Commit le renommage du projet")
                }
            }
            onFailure {
                instruction("Dis moi pourquoi le renommage a échoué")
            }
        }
    }
}