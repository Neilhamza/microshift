package prerun

import (
	"fmt"
	"strings"

	"github.com/openshift/microshift/pkg/admin/data"

	"k8s.io/apimachinery/pkg/util/sets"
	"k8s.io/klog/v2"
)

type Backups []data.BackupName

func getBackups(dataManager data.Manager) (Backups, error) {
	backups, err := dataManager.GetBackupList()
	if err != nil {
		return nil, fmt.Errorf("failed to get existing backups: %w", err)
	}
	klog.InfoS("List of existing backups", "backups", backups)
	return backups, nil
}

func (bs Backups) filter(pred func(data.BackupName) bool) Backups {
	filtered := []data.BackupName{}
	for _, b := range bs {
		if pred(b) {
			filtered = append(filtered, b)
		}
	}
	return filtered
}

func (bs Backups) getForDeployment(deploymentID string) Backups {
	backups := bs.filter(func(backupName data.BackupName) bool {
		return strings.HasPrefix(string(backupName), deploymentID)
	})
	klog.InfoS("Filtered list of backups for the deployment",
		"deploymentID", deploymentID,
		"backups", backups,
	)
	return backups
}

func (bs Backups) getOnlyHealthyBackups() Backups {
	backups := bs.filter(func(backupName data.BackupName) bool {
		return !strings.HasSuffix(string(backupName), "unhealthy")
	})
	klog.InfoS("Filtered list of healthy backups",
		"backups", backups,
	)
	return backups
}

func (bs Backups) has(backup data.BackupName) bool {
	for _, b := range bs {
		if b == backup {
			return true
		}
	}
	return false
}

func (bs Backups) removeAll(dataManager data.Manager) {
	if len(bs) == 0 {
		return
	}

	klog.Info("Starting pruning backups")
	defer klog.Info("Finished pruning backups")

	for _, b := range bs {
		if err := dataManager.RemoveBackup(b); err != nil {
			klog.ErrorS(err, "Failed to remove backup - ignoring", "name", b)
		}
	}
}

func (bs Backups) getOneOrNone() data.BackupName {
	if len(bs) > 0 {
		return bs[0]
	}
	return ""
}

// getDangling filters backups using given list of deployments
// and returns a list of backups that do not belong to any of these deployments
func (bs Backups) getDangling(deploymentIDs []string) Backups {
	backupsToRemove := []data.BackupName{}
	unknownDeployments := []data.BackupName{}

	ds := sets.New(deploymentIDs...)

	for _, b := range bs {
		deploy := getDeploymentIDForTheBackup(b)

		if deploy != "" {
			if !ds.Has(deploy) {
				backupsToRemove = append(backupsToRemove, b)
			}
		} else {
			unknownDeployments = append(unknownDeployments, b)
		}
	}

	if len(unknownDeployments) > 0 {
		// Expecting to be "4.13"
		klog.InfoS("Found backups not belonging to any deployment - they need to be deleted manually", "backups", unknownDeployments)
	}

	return backupsToRemove
}

// getDeploymentIDForTheBackup returns a deployment ID from backup's name
// according to the schema: deploy-id_boot-id
func getDeploymentIDForTheBackup(backup data.BackupName) string {
	spl := strings.Split(string(backup), "_")
	if len(spl) > 1 {
		return spl[0]
	}
	return ""
}
