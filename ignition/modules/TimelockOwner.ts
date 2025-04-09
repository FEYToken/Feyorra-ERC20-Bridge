import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const TimelockOwnerModule = buildModule("TimelockOwnerModule", (m) => {
  const minDelaySeconds = m.getParameter("minDelaySeconds", 86_400);
  const proposers = m.getParameter("proposers", []);
  const executors = m.getParameter("executors", []);

  const timelockOwner = m.contract("TimelockOwner", [
    minDelaySeconds,
    proposers,
    executors,
  ]);

  return { timelockOwner };
});

export default TimelockOwnerModule;
