import { execFileSync } from "node:child_process";
import { randomBytes } from "node:crypto";

export function newFixture() {
  const id = randomBytes(6).toString("hex");
  return {
    isbn: `e2e-${id}`,
    email: `acceptance-${id}@bookstore.test`,
    title: `BookStore acceptance ${id}`,
  };
}

export function executeFixture(sql) {
  const task = JSON.parse(process.env.BOOTSTRAP_TASK);
  if (
    process.env.TF_WORKSPACE !== "staging"
    || task.cluster !== "bookstore-staging"
    || !/:task-definition\/bookstore-staging-db-bootstrap:\d+$/.test(task.taskDefinition)
  ) {
    throw new Error("Purchase fixtures are restricted to the staging database task");
  }

  const aws = (...args) => execFileSync("aws", [
    "--region", process.env.AWS_REGION || "us-east-1", "--no-cli-pager", ...args,
  ], { encoding: "utf8", timeout: 240_000 }).trim();
  const command = [
    'export PGPASSWORD="$DB_ADMIN_PASSWORD"',
    'psql -X -v ON_ERROR_STOP=1 -h "$DB_HOST" -p "$DB_PORT" -U "$DB_ADMIN_USER" -d "$DB_NAME" <<\'BOOKSTORE_SQL\'',
    sql,
    "BOOKSTORE_SQL",
  ].join("\n");

  const started = JSON.parse(aws("ecs", "run-task", "--output", "json", "--cli-input-json",
    JSON.stringify({
      ...task,
      overrides: { containerOverrides: [{ name: "bootstrap", command: [command] }] },
    })));
  const taskArn = started.tasks[0]?.taskArn;
  if (!taskArn) {
    throw new Error(`Unable to launch staging fixture task: ${JSON.stringify(started.failures)}`);
  }

  aws("ecs", "wait", "tasks-stopped", "--cluster", task.cluster, "--tasks", taskArn);
  const result = JSON.parse(aws("ecs", "describe-tasks", "--cluster", task.cluster,
    "--tasks", taskArn, "--output", "json")).tasks[0];
  const container = result?.containers.find(({ name }) => name === "bootstrap");
  if (container?.exitCode !== 0) {
    throw new Error(`Staging fixture task ${taskArn} failed: ${container?.reason || result?.stoppedReason}`);
  }
}
