.PHONY: test test-e2e lint

test:
	bash test/unit.sh

test-e2e:
	bash test/e2e.sh

lint:
	shellcheck -S warning bin/rex-agent-restore share/rex-agent-restore/rex-agent-restore.bash test/*.sh
