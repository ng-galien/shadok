

pipeline {
    with("project.md")
    stage("Associer le projet à un dépôt GitHub") {
        input("repositoryName", "ng-galien/shadok") 
        mcp("github") {
            configureProject(
                instruction("Configurer le projet pour l'association avec GitHub") {
                    args: repositoryName: "${repositoryName}",
                }
            )
        }
    }
    stage("configurer") {
        with(tool("git")) {
            instruction("Configurer le fichier .gitignore pour le projet")
            commit{
                instruction("Commit les changements de configuration")
            }
            push("main")
        }
        result {
            onSuccess {
                output("Le projet est associé au dépôt GitHub : ${repositoryName}")
            }
            onFailure {
                instruction("Dis moi pourquoi l'association a échoué")
            }
        }
    }    
}