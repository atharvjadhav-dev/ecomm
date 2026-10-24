import type { MedusaRequest, MedusaResponse } from "@medusajs/framework/http";
import { GET as storeCustomGet } from "../store/custom/route";
import { GET as adminCustomGet } from "../admin/custom/route";
import { toOptionValues } from "../../search/helpers/option-values";

describe("Backend Route & Utility Unit Tests", () => {
  describe("Custom health/status route handlers", () => {
    it("responds with HTTP 200 on /store/custom GET", async () => {
      const req = {} as MedusaRequest;
      const res = {
        sendStatus: jest.fn(),
      } as unknown as MedusaResponse;

      await storeCustomGet(req, res);
      expect(res.sendStatus).toHaveBeenCalledWith(200);
    });

    it("responds with HTTP 200 on /admin/custom GET", async () => {
      const req = {} as MedusaRequest;
      const res = {
        sendStatus: jest.fn(),
      } as unknown as MedusaResponse;

      await adminCustomGet(req, res);
      expect(res.sendStatus).toHaveBeenCalledWith(200);
    });
  });

  describe("Search helper: toOptionValues", () => {
    it("flattens and deduplicates product option rows", () => {
      const options = [
        {
          title: "Size",
          values: [{ value: "S" }, { value: "M" }, { value: "S" }],
        },
        {
          title: " Color ",
          values: [{ value: " Black " }, { value: null }],
        },
      ];

      expect(toOptionValues(options)).toEqual(["Size:S", "Size:M", "Color:Black"]);
    });

    it("returns an empty array for null or empty options", () => {
      expect(toOptionValues(null)).toEqual([]);
      expect(toOptionValues(undefined)).toEqual([]);
      expect(toOptionValues([{ title: "  ", values: [{ value: "S" }] }])).toEqual([]);
    });
  });
});
